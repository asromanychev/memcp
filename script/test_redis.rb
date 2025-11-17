#!/usr/bin/env ruby
# frozen_string_literal: true

# Простой скрипт для проверки Redis без полной инициализации Rails
require 'redis'

redis_host = ENV.fetch('REDIS_HOST', 'localhost')
redis_port = ENV.fetch('REDIS_PORT', 6379).to_i

puts "Testing Redis connection..."
puts "Host: #{redis_host}, Port: #{redis_port}"

begin
  redis = Redis.new(host: redis_host, port: redis_port, db: 0)
  result = redis.ping
  puts "✅ Redis ping: #{result}"
  
  # Проверка конфигурации для Sidekiq (db: 1)
  redis_sidekiq = Redis.new(host: redis_host, port: redis_port, db: 1)
  result_sidekiq = redis_sidekiq.ping
  puts "✅ Redis Sidekiq (db: 1) ping: #{result_sidekiq}"
  
  # Проверка записи/чтения
  redis.set('test_key', 'test_value')
  value = redis.get('test_key')
  puts "✅ Redis read/write test: #{value}"
  redis.del('test_key')
  
  puts "\n✅ All Redis tests passed!"
  exit 0
rescue => e
  puts "❌ Redis test failed: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end


