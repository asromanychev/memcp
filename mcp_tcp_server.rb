#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'socket'
require 'net/http'
require 'uri'

# MCP TCP Server для долгосрочной памяти
# Работает как TCP сервер, принимающий MCP протокол по TCP
class MCPTCPServer
  API_BASE_URL = ENV.fetch('MEMCP_API_URL', 'http://localhost:3001').freeze
  DEFAULT_PORT = ENV.fetch('MCP_TCP_PORT', '3002').to_i
  DEFAULT_HOST = ENV.fetch('MCP_TCP_HOST', '0.0.0.0').freeze

  def initialize(port: DEFAULT_PORT, host: DEFAULT_HOST)
    @port = port
    @host = host
    @server = nil
  end

  def start
    @server = TCPServer.new(@host, @port)
    puts "MCP TCP Server listening on #{@host}:#{@port}"
    puts "API endpoint: #{API_BASE_URL}"

    loop do
      client = @server.accept
      Thread.new(client) { |c| handle_client(c) }
    end
  rescue Interrupt
    puts "\nShutting down server..."
    @server&.close
  end

  private

  def handle_client(client)
    client_ip = "#{client.peeraddr[2]}:#{client.peeraddr[1]}"
    puts "Client connected: #{client_ip}"
    
    # Устанавливаем таймауты для чтения
    client.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    
    loop do
      # Читаем с таймаутом (5 секунд на чтение)
      ready = IO.select([client], nil, nil, 5)
      break unless ready
      
      line = client.gets
      break if line.nil?
      
      # Пропускаем пустые строки
      next if line.strip.empty?

      request = parse_request(line, client)
      next if request.nil?

      response = handle_request(request)
      send_response(client, response) if response
    end
  rescue EOFError, Errno::ECONNRESET
    puts "Client disconnected: #{client_ip}"
  rescue StandardError => e
    puts "Error handling client #{client_ip}: #{e.message}"
    puts e.backtrace.first(3)
    send_error(client, 0, -32603, "Internal error: #{e.message}")
  ensure
    client.close
    puts "Connection closed: #{client_ip}"
  end

  def parse_request(line, client = nil)
    JSON.parse(line.strip)
  rescue JSON::ParserError => e
    send_error(client, 0, -32700, "Parse error: #{e.message}") if client
    nil
  end

  def handle_request(request)
    return nil unless request.is_a?(Hash)

    method = request['method']
    id = request['id']
    params = request['params'] || {}

    unless method
      return error_response(id || 0, -32600, "Invalid Request: method is required") if id
      return nil
    end

    # Обработка уведомлений
    if method.start_with?('notifications/')
      return nil # Уведомления не требуют ответа
    end

    # Методы требуют id
    unless id
      return error_response(0, -32600, "Invalid Request: method requires id")
    end

    case method
    when 'initialize'
      initialize_response(id, params)
    when 'tools/list'
      tools_list_response(id, params)
    when 'tools/call'
      tools_call_response(id, params)
    else
      error_response(id || 0, -32601, "Method not found: #{method}")
    end
  end

  def initialize_response(id, params)
    {
      jsonrpc: '2.0',
      id: id,
      result: {
        protocolVersion: '2024-11-05',
        capabilities: {
          tools: {}
        },
        serverInfo: {
          name: 'memcp-tcp-server',
          version: '1.0.0'
        }
      }
    }
  end

  def tools_list_response(id, params)
    {
      jsonrpc: '2.0',
      id: id,
      result: {
        tools: [
          {
            name: 'recall',
            description: 'Recall memory bundle based on project/task context',
            inputSchema: {
              type: 'object',
              properties: {
                project_key: { type: 'string', description: 'Project key' },
                task_external_id: { type: 'string', description: 'Tracker issue id' },
                repo_path: { type: 'string' },
                symbols: { type: 'array', items: { type: 'string' } },
                signals: { type: 'array', items: { type: 'string' } },
                limit_tokens: { type: 'number' }
              },
              required: ['project_key']
            }
          },
          {
            name: 'save',
            description: 'Save a distilled memory record',
            inputSchema: {
              type: 'object',
              properties: {
                project_key: { type: 'string' },
                task_external_id: { type: 'string' },
                kind: { type: 'string', description: 'fact|fewshot|pattern|adr_link|gotcha|rule' },
                content: { type: 'string' },
                scope: { type: 'array', items: { type: 'string' } },
                tags: { type: 'array', items: { type: 'string' } },
                owner: { type: 'string' },
                ttl: { type: 'string', description: 'ISO timestamp' },
                quality: { type: 'object' },
                meta: { type: 'object' }
              },
              required: ['project_key', 'kind', 'content']
            }
          }
        ]
      }
    }
  end

  def tools_call_response(id, params)
    tool_name = params['name']
    arguments = params['arguments'] || {}

    unless tool_name
      return error_response(id, -32602, "Tool name is required")
    end

    case tool_name
    when 'recall'
      result = call_recall(arguments)
      {
        jsonrpc: '2.0',
        id: id,
        result: {
          content: [
            {
              type: 'text',
              text: JSON.pretty_generate(result)
            }
          ]
        }
      }
    when 'save'
      result = call_save(arguments)
      {
        jsonrpc: '2.0',
        id: id,
        result: {
          content: [
            {
              type: 'text',
              text: JSON.pretty_generate(result)
            }
          ]
        }
      }
    else
      error_response(id, -32602, "Unknown tool: #{tool_name}")
    end
  rescue StandardError => e
    error_response(id, -32603, "Tool execution error: #{e.message}")
  end

  def call_recall(params)
    body = {
      project_key: params['project_key'] || params[:project_key],
      task_external_id: params['task_external_id'] || params[:task_external_id],
      repo_path: params['repo_path'] || params[:repo_path],
      symbols: params['symbols'] || params[:symbols],
      signals: params['signals'] || params[:signals],
      limit_tokens: params['limit_tokens'] || params[:limit_tokens]
    }.compact

    uri = URI("#{API_BASE_URL}/recall")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 30
    request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
    request.body = JSON.generate(body)

    response = http.request(request)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "API returned error: #{response.code} #{response.message}"
    end
    
    JSON.parse(response.body)
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
    raise "Cannot connect to API at #{API_BASE_URL}: #{e.message}. Check if Rails server is running."
  rescue Net::ReadTimeout => e
    raise "API request timeout: #{e.message}"
  rescue JSON::ParserError => e
    raise "Invalid JSON response from API: #{e.message}"
  end

  def call_save(params)
    body = {
      project_key: params['project_key'] || params[:project_key],
      task_external_id: params['task_external_id'] || params[:task_external_id],
      kind: params['kind'] || params[:kind],
      content: params['content'] || params[:content],
      scope: params['scope'] || params[:scope],
      tags: params['tags'] || params[:tags],
      owner: params['owner'] || params[:owner],
      ttl: params['ttl'] || params[:ttl],
      quality: params['quality'] || params[:quality],
      meta: params['meta'] || params[:meta]
    }.compact

    uri = URI("#{API_BASE_URL}/save")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 30
    request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
    request.body = JSON.generate(body)

    response = http.request(request)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "API returned error: #{response.code} #{response.message}"
    end
    
    JSON.parse(response.body)
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
    raise "Cannot connect to API at #{API_BASE_URL}: #{e.message}. Check if Rails server is running."
  rescue Net::ReadTimeout => e
    raise "API request timeout: #{e.message}"
  rescue JSON::ParserError => e
    raise "Invalid JSON response from API: #{e.message}"
  end

  def send_response(client, response)
    return unless client
    client.puts(JSON.generate(response))
    client.flush
  end

  def send_error(client, id, code, message)
    return unless client
    response_id = id.nil? ? 0 : id
    send_response(client, error_response(response_id, code, message))
  end

  def error_response(id, code, message)
    {
      jsonrpc: '2.0',
      id: id,
      error: {
        code: code,
        message: message
      }
    }
  end
end

# Запуск сервера
if __FILE__ == $PROGRAM_NAME
  port = (ARGV[0] || ENV['MCP_TCP_PORT'] || '3002').to_i
  host = ARGV[1] || ENV['MCP_TCP_HOST'] || '0.0.0.0'
  
  server = MCPTCPServer.new(port: port, host: host)
  server.start
end
