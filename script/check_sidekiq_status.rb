# frozen_string_literal: true

# Скрипт для проверки статуса Sidekiq
# Запускать через: rails runner script/check_sidekiq_status.rb

require 'sidekiq/api'

puts "=== Sidekiq Status ==="
puts

# Статистика очередей
stats = Sidekiq::Stats.new
puts "📊 Общая статистика:"
puts "  Обработано: #{stats.processed}"
puts "  Неудачных: #{stats.failed}"
puts "  В очереди: #{stats.enqueued}"
puts "  В процессе: #{stats.busy}"
puts "  Запланировано: #{stats.scheduled_size}"
puts "  Retry: #{stats.retry_size}"
puts "  Dead: #{stats.dead_size}"
puts

# Детали по очередям
puts "📋 Очереди:"
Sidekiq::Queue.all.each do |queue|
  puts "  #{queue.name}:"
  puts "    Размер: #{queue.size}"
  puts "    Латентность: #{queue.latency.round(2)}s"
  if queue.size > 0
    puts "    Первая задача: #{queue.first&.item&.dig('created_at')}"
  end
  puts
end

# Задачи в процессе
if stats.busy > 0
  puts "⚙️  Задачи в процессе:"
  Sidekiq::Workers.new.each do |process_id, thread_id, work|
    puts "  Process: #{process_id}"
    puts "    Queue: #{work['queue']}"
    puts "    Class: #{work['payload']['class']}"
    puts "    Args: #{work['payload']['args'].inspect}"
    puts "    Started: #{Time.at(work['run_at'])}"
    puts
  end
end

# Запланированные задачи
scheduled = Sidekiq::ScheduledSet.new
if scheduled.size > 0
  puts "⏰ Запланированные задачи: #{scheduled.size}"
  scheduled.each do |job|
    puts "  #{job.klass} - #{Time.at(job.at)}"
  end
  puts
end

# Retry задачи
retry_set = Sidekiq::RetrySet.new
if retry_set.size > 0
  puts "🔄 Retry задачи: #{retry_set.size}"
  retry_set.each do |job|
    puts "  #{job.klass} - Попытка #{job['retry_count']}/#{job['retry']}"
  end
  puts
end

# Dead задачи
dead_set = Sidekiq::DeadSet.new
if dead_set.size > 0
  puts "💀 Dead задачи: #{dead_set.size}"
  dead_set.each do |job|
    puts "  #{job.klass} - #{job.error_message}"
  end
  puts
end

puts "✅ Проверка завершена"

