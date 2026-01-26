#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'socket'

# MCP TCP Client - STDIO прокси для подключения к TCP MCP серверу
# Используется в Cursor IDE вместо прямого подключения к TCP
class MCPTCPClient
  DEFAULT_HOST = ENV.fetch('MCP_TCP_HOST', '192.168.0.93').freeze
  DEFAULT_PORT = ENV.fetch('MCP_TCP_PORT', '3002').to_i

  def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT)
    @host = host
    @port = port
    @socket = nil
  end

  def connect
    @socket = TCPSocket.new(@host, @port)
    true
  rescue Errno::ECONNREFUSED => e
    STDERR.puts "Connection refused to MCP TCP server at #{@host}:#{@port}"
    STDERR.puts "Check if TCP server is running on the server laptop"
    false
  rescue Errno::ETIMEDOUT => e
    STDERR.puts "Connection timeout to MCP TCP server at #{@host}:#{@port}"
    STDERR.puts "Check network connectivity and firewall settings"
    false
  rescue Errno::EHOSTUNREACH => e
    STDERR.puts "No route to host #{@host}:#{@port}"
    STDERR.puts "Possible causes:"
    STDERR.puts "  1. TCP server is not running on server laptop"
    STDERR.puts "  2. Firewall is blocking port #{@port}"
    STDERR.puts "  3. Wrong IP address: #{@host}"
    STDERR.puts "  4. Network connectivity issues"
    STDERR.puts "Check: ping #{@host} and verify TCP server is running"
    false
  rescue SocketError => e
    STDERR.puts "Socket error connecting to MCP TCP server at #{@host}:#{@port}: #{e.message}"
    false
  end

  def run
    return unless connect

    # Устанавливаем таймауты
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

    # Читаем из STDIN и отправляем в TCP сокет
    # Читаем из TCP сокета и отправляем в STDOUT
    reader = Thread.new do
      begin
        loop do
          line = @socket.gets
          break if line.nil?
          STDOUT.puts line
          STDOUT.flush
        end
      rescue EOFError, Errno::ECONNRESET
        # Соединение закрыто сервером
        exit 0
      rescue StandardError => e
        STDERR.puts "Reader error: #{e.message}"
        exit 1
      end
    end

    writer = Thread.new do
      begin
        loop do
          line = STDIN.gets
          break if line.nil?
          # Отправляем даже пустые строки, но не прерываем на них
          @socket.puts line
          @socket.flush
        end
      rescue EOFError
        # STDIN закрыт - закрываем сокет для чтения
        @socket.close_write
      rescue StandardError => e
        STDERR.puts "Writer error: #{e.message}"
        exit 1
      end
    end

    # Ждем завершения потоков
    reader.join
    writer.join
  ensure
    @socket&.close
  end
end

# Запуск клиента
if __FILE__ == $PROGRAM_NAME
  host = ARGV[0] || ENV['MCP_TCP_HOST'] || '192.168.0.93'
  port = (ARGV[1] || ENV['MCP_TCP_PORT'] || '3002').to_i

  client = MCPTCPClient.new(host: host, port: port)
  client.run
end
