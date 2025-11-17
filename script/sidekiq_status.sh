#!/bin/bash
# Быстрая проверка статуса Sidekiq

echo "=== Sidekiq Status ==="
echo

# Через Rails runner
docker-compose exec web bundle exec rails runner '
require "sidekiq/api"
stats = Sidekiq::Stats.new
puts "📊 Статистика:"
puts "  ✅ Обработано: #{stats.processed}"
puts "  ❌ Неудачных: #{stats.failed}"
puts "  📥 В очереди: #{stats.enqueued}"
puts "  ⚙️  В процессе: #{Sidekiq::Workers.new.size}"
puts "  🔄 Retry: #{stats.retry_size}"
puts "  💀 Dead: #{stats.dead_size}"
puts

Sidekiq::Queue.all.each do |queue|
  puts "📋 Очередь #{queue.name}: #{queue.size} задач"
end

if stats.dead_size > 0
  puts
  puts "💀 Dead задачи (первые 5):"
  Sidekiq::DeadSet.new.first(5).each do |job|
    puts "  - #{job.klass}: #{job.error_message}"
  end
end
' 2>&1 | grep -v "INFO: Sidekiq"

