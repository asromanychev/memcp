# frozen_string_literal: true

# Скрипт для проверки импортированных знаний

project = Project.find_by(key: "insales")
unless project
  puts "❌ Проект 'insales' не найден"
  exit 1
end

puts "=" * 80
puts "ПРОВЕРКА ИМПОРТИРОВАННЫХ ЗНАНИЙ"
puts "=" * 80
puts

total_records = project.memory_records.count
puts "📊 Всего записей в проекте: #{total_records}"

# Статистика по типам
kinds = project.memory_records.group(:kind).count
puts "\n📋 Статистика по типам:"
kinds.each do |kind, count|
  puts "  #{kind}: #{count}"
end

# Проверка тегов
puts "\n🏷️  Топ-10 тегов:"
tag_counts = project.memory_records.where.not(tags: nil).pluck(:tags).flatten.compact.group_by(&:itself).transform_values(&:count).sort_by { |_k, v| -v }.first(10)
tag_counts.each do |tag, count|
  puts "  #{tag}: #{count}"
end

# Проверка поиска по сигналам
puts "\n" + "=" * 80
puts "ТЕСТЫ ПОИСКА"
puts "=" * 80

test_cases = [
  { signals: ["security", "idor"], description: "Поиск security/idor" },
  { signals: ["redis", "infrastructure"], description: "Поиск redis/infrastructure" },
  { signals: ["n+1", "optimization"], description: "Поиск n+1/optimization" },
  { signals: ["rails"], description: "Поиск rails" },
  { signals: ["sidekiq"], description: "Поиск sidekiq" }
]

test_cases.each do |test|
  service = Memories::RecallService.call(
    params: {
      project_key: "insales",
      signals: test[:signals],
      limit_tokens: 2000
    }
  )
  
  if service.success?
    result = service.result
    puts "\n#{test[:description]}:"
    puts "  facts: #{result[:facts].count}"
    puts "  few_shots: #{result[:few_shots].count}"
    puts "  confidence: #{result[:confidence]}"
    
    if result[:facts].any?
      puts "  Примеры facts:"
      result[:facts].first(3).each_with_index do |fact, i|
        preview = fact[:text][0..80].gsub(/\n/, ' ')
        puts "    #{i + 1}. #{preview}..."
      end
    end
  else
    puts "\n#{test[:description]}: ❌ Ошибка - #{service.errors.full_messages.join(', ')}"
  end
end

puts "\n" + "=" * 80
puts "ПРОВЕРКА ЗАВЕРШЕНА"
puts "=" * 80


