#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# MCP Server для долгосрочной памяти
class MCPServer
  API_BASE_URL = ENV.fetch('MEMCP_API_URL', 'http://localhost:3101').freeze

  def initialize
    @server_ready = false
  end

  def run
    # Основной цикл обработки запросов
    loop do
      request = read_request
      break if request.nil?

      handle_request(request)
    end
  rescue StandardError => e
    send_error(0, -32603, "Internal error: #{e.message}")
    raise
  rescue Interrupt
    # Graceful shutdown
    exit 0
  end

  private

  def read_request
    line = STDIN.gets
    return nil if line.nil? || line.strip.empty?

    parsed = JSON.parse(line)
    parsed
  rescue JSON::ParserError => e
    # Для ошибок парсинга не можем получить id из запроса, используем 0
    send_error(0, -32700, "Parse error: #{e.message}")
    nil
  end

  def send_response(response)
    puts JSON.generate(response)
    STDOUT.flush
  end

  def send_error(id, code, message)
    # MCP требует, чтобы id был строкой или числом, не nil
    # Если id nil, используем 0 как fallback
    response_id = id.nil? ? 0 : id

    send_response({
      jsonrpc: '2.0',
      id: response_id,
      error: {
        code: code,
        message: message
      }
    })
  end

  def handle_request(request)
    # Проверяем, что это валидный JSON-RPC запрос
    return unless request.is_a?(Hash)

    method = request['method']
    id = request['id']
    params = request['params'] || {}

    # Если method отсутствует, это не валидный запрос
    unless method
      send_error(id || 0, -32600, "Invalid Request: method is required")
      return
    end

    case method
    when 'initialize'
      handle_initialize(id, params)
    when 'tools/list'
      handle_tools_list(id, params)
    when 'tools/call'
      handle_tool_call(id, params)
    else
      send_error(id || 0, -32601, "Method not found: #{method}")
    end
  end

  def handle_tools_list(id, params)
    # id должен быть строкой или числом
    response_id = id.nil? ? 0 : id

    send_response({
      jsonrpc: '2.0',
      id: response_id,
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
              required: [ 'project_key' ]
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
              required: [ 'project_key', 'kind', 'content' ]
            }
          }
        ]
      }
    })
  end

  def handle_initialize(id, params)
    # id должен быть строкой или числом
    response_id = id.nil? ? 0 : id

    send_response({
      jsonrpc: '2.0',
      id: response_id,
      result: {
        protocolVersion: '2024-11-05',
        capabilities: {
          tools: {}
        },
        serverInfo: {
          name: 'memcp-server',
          version: '1.0.0'
        }
      }
    })
  end

  def handle_tool_call(id, params)
    # id должен быть строкой или числом
    response_id = id.nil? ? 0 : id

    tool_name = params['name']
    arguments = params['arguments'] || {}

    unless tool_name
      send_error(response_id, -32602, "Tool name is required")
      return
    end

    case tool_name
    when 'recall'
      result = call_recall(arguments)
      send_response({
        jsonrpc: '2.0',
        id: response_id,
        result: {
          content: [
            {
              type: 'text',
              text: JSON.pretty_generate(result)
            }
          ]
        }
      })
    when 'save'
      result = call_save(arguments)
      send_response({
        jsonrpc: '2.0',
        id: response_id,
        result: {
          content: [
            {
              type: 'text',
              text: JSON.pretty_generate(result)
            }
          ]
        }
      })
    else
      send_error(response_id, -32602, "Unknown tool: #{tool_name}")
    end
  rescue StandardError => e
    response_id = id.nil? ? 0 : id
    send_error(response_id, -32603, "Tool execution error: #{e.message}")
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
    request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
    request.body = JSON.generate(body)

    response = http.request(request)
    JSON.parse(response.body)
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
    request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
    request.body = JSON.generate(body)

    response = http.request(request)
    JSON.parse(response.body)
  end
end

# Запуск сервера
if __FILE__ == $PROGRAM_NAME
  server = MCPServer.new
  server.run
end
