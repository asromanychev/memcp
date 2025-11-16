#!/usr/bin/env ruby
# frozen_string_literal: true
# Скрипт для проверки работы дедупликации

require_relative "config/environment"

puts "=" * 80
puts "Тест дедупликации MemCP"
puts "=" * 80
puts

# Очистка старых данных для чистого теста
project_key = "test_dedup"
project = Project.find_by(key: project_key)
if project
  puts "Удаляем старые записи проекта #{project_key}..."
  project.memory_records.destroy_all
end

puts "\n1. Создаем ПЕРВУЮ запись (оригинал)"
puts "-" * 80

content1 = "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать. Добавлена валидация в модель."

service1 = Memories::SaveService.call(params: {
  project_key: project_key,
  kind: "fact",
  content: content1,
  scope: ["cart_sessions", "settings"],
  tags: ["bugfix", "validation"],
  owner: "test"
})

if service1.success?
  record1 = MemoryRecord.find(service1.result[:id])
  puts "✅ Запись создана: ID=#{record1.id}"
  puts "   Content: #{record1.content[0..60]}..."
  puts "   SimHash: #{record1.simhash}"
  puts "   MinHash: #{record1.minhash&.first(3)&.join(', ')}... (#{record1.minhash&.size} хешей)"
  puts "   Tags: #{record1.tags.inspect}"
else
  puts "❌ Ошибка: #{service1.errors.full_messages.join(', ')}"
  exit 1
end

puts "\n2. Создаем ВТОРУЮ запись (похожая, с небольшими изменениями)"
puts "-" * 80

# Похожий контент с небольшими изменениями
content2 = "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать. Добавлена валидация в модель CartSessions::Setting."

service2 = Memories::SaveService.call(params: {
  project_key: project_key,
  kind: "fact",
  content: content2,
  scope: ["cart_sessions", "settings"],
  tags: ["bugfix", "validation", "unit"], # Добавили новый тег
  owner: "test"
})

if service2.success?
  record2_id = service2.result[:id]
  record2 = MemoryRecord.find(record2_id)
  puts "✅ Обработка завершена: ID=#{record2.id}"
  puts "   Content: #{record2.content[0..60]}..."
  puts "   SimHash: #{record2.simhash}"
  puts "   Tags: #{record2.tags.inspect}"
else
  puts "❌ Ошибка: #{service2.errors.full_messages.join(', ')}"
  exit 1
end

puts "\n3. Проверяем результат дедупликации"
puts "-" * 80

all_records = Project.find_by(key: project_key).memory_records.order(:id)
puts "Всего записей в проекте: #{all_records.count}"

if all_records.count == 1
  puts "✅ ДЕДУПЛИКАЦИЯ РАБОТАЕТ! Вторая запись обновила первую вместо создания дубликата"
  final_record = all_records.first
  puts "\n   Финальная запись:"
  puts "   ID: #{final_record.id}"
  puts "   Content: #{final_record.content}"
  puts "   Tags: #{final_record.tags.inspect} (объединены из обеих записей)"
  puts "   Updated at: #{final_record.updated_at}"
else
  puts "❌ ДЕДУПЛИКАЦИЯ НЕ СРАБОТАЛА! Создано #{all_records.count} записей вместо 1"
  all_records.each do |r|
    puts "   - ID=#{r.id}, content=#{r.content[0..40]}..."
  end
end

puts "\n4. Проверяем поиск похожих записей"
puts "-" * 80

test_content = "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать"
similar = MemoryRecord.find_similar(
  content: test_content,
  project_id: Project.find_by(key: project_key).id,
  threshold: 0.85
)

puts "Найдено похожих записей: #{similar.count}"
if similar.any?
  similar.each do |r|
    similarity = MemoryRecord.jaccard_similarity(
      Memories::DeduplicationService.call(params: { content: test_content }).result[:minhash],
      r.minhash || []
    )
    puts "   - ID=#{r.id}, similarity=#{similarity.round(3)}, content=#{r.content[0..50]}..."
  end
end

puts "\n5. Тест с НЕпохожим контентом"
puts "-" * 80

different_content = "В проекте используется паттерн Service Objects с единым интерфейсом .call(params:)"
service3 = Memories::SaveService.call(params: {
  project_key: project_key,
  kind: "pattern",
  content: different_content,
  scope: ["architecture"],
  tags: ["pattern", "service-objects"],
  owner: "test"
})

if service3.success?
  record3 = MemoryRecord.find(service3.result[:id])
  puts "✅ Создана новая запись (не похожая на предыдущие): ID=#{record3.id}"
  puts "   Content: #{record3.content[0..60]}..."
else
  puts "❌ Ошибка: #{service3.errors.full_messages.join(', ')}"
end

final_count = Project.find_by(key: project_key).memory_records.count
puts "\nИтого записей в проекте: #{final_count}"
puts "   (ожидается 2: одна из шага 1-2, одна из шага 5)"

puts "\n" + "=" * 80
puts "Тест завершен!"
puts "=" * 80

