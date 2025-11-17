# frozen_string_literal: true

# Скрипт для проверки Redis и Sidekiq
# Запускать через: rails runner script/check_redis_sidekiq.rb

puts "=== Redis Connection Test ==="
begin
  result = $redis.ping
  puts "✅ Redis ping: #{result}"
rescue => e
  puts "❌ Redis error: #{e.class} - #{e.message}"
  exit 1
end

puts "\n=== Sidekiq Redis Connection Test ==="
begin
  result = Sidekiq.redis { |conn| conn.ping }
  puts "✅ Sidekiq redis ping: #{result}"
rescue => e
  puts "❌ Sidekiq redis error: #{e.class} - #{e.message}"
  exit 1
end

puts "\n=== Redis Configuration ==="
puts "REDIS_CONFIG[:default]: #{REDIS_CONFIG[:default].inspect}"
puts "REDIS_CONFIG[:sidekiq]: #{REDIS_CONFIG[:sidekiq].inspect}"

puts "\n=== Test Job Enqueue ==="
begin
  job_id = TestJob.perform_async("Hello from Sidekiq test")
  puts "✅ TestJob enqueued with ID: #{job_id}"
rescue => e
  puts "❌ TestJob error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

puts "\n✅ All tests passed!"

