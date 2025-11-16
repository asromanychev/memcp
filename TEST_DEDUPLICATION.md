# Тестирование дедупликации

## Быстрая проверка через Rails console

### Вариант 1: Автоматический тест

```bash
bin/rails runner test_deduplication_simple.rb
```

Этот скрипт:
1. Создает первую запись
2. Создает вторую похожую запись
3. Проверяет, что вторая запись обновила первую (дедупликация сработала)
4. Создает непохожую запись (должна создать новую)
5. Показывает метрики схожести (Hamming distance, Jaccard similarity)

### Вариант 2: Ручная проверка через Rails console

```bash
bin/rails console
```

```ruby
# 1. Создаем первую запись
service1 = Memories::SaveService.call(params: {
  project_key: "test",
  kind: "fact",
  content: "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать",
  tags: ["bugfix"]
})

record1_id = service1.result[:id]
puts "Первая запись: ID=#{record1_id}"

# 2. Создаем вторую похожую запись (с небольшими изменениями)
service2 = Memories::SaveService.call(params: {
  project_key: "test",
  kind: "fact",
  content: "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать. Добавлена валидация.",
  tags: ["bugfix", "validation"] # Добавили тег
})

record2_id = service2.result[:id]
puts "Вторая запись: ID=#{record2_id}"

# 3. Проверяем результат
project = Project.find_by(key: "test")
all_records = project.memory_records.count

if all_records == 1 && record1_id == record2_id
  puts "✅ ДЕДУПЛИКАЦИЯ РАБОТАЕТ! Вторая запись обновила первую"
  record = MemoryRecord.find(record1_id)
  puts "   Теги объединены: #{record.tags.inspect}"
else
  puts "❌ Дедупликация не сработала. Записей: #{all_records}"
end
```

### Вариант 3: Проверка через API

```bash
# Первая запись
curl -X POST http://localhost:3001/save \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "test",
    "kind": "fact",
    "content": "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать",
    "tags": ["bugfix"]
  }'

# Вторая похожая запись (должна обновить первую)
curl -X POST http://localhost:3001/save \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "test",
    "kind": "fact",
    "content": "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать. Добавлена валидация.",
    "tags": ["bugfix", "validation"]
  }'

# Проверяем количество записей
curl -X POST http://localhost:3001/recall \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "test"
  }'
```

## Что проверяет тест

1. **Дедупликация работает**: вторая похожая запись обновляет первую вместо создания дубликата
2. **Объединение тегов**: теги из обеих записей объединяются
3. **Обновление контента**: если новый контент длиннее, он заменяет старый
4. **Непохожий контент**: записи с низкой схожестью создаются как новые
5. **Метрики**: Hamming distance и Jaccard similarity рассчитываются корректно

## Ожидаемые результаты

- **Похожие записи** (Jaccard similarity ≥ 0.85): обновляют существующую запись
- **Непохожие записи** (Jaccard similarity < 0.85): создают новую запись
- **Hamming distance**: для threshold 0.85 максимум ≈ 10 бит
- **Jaccard similarity**: для похожих текстов обычно > 0.9

## Пример вывода успешного теста

```
✅ ДЕДУПЛИКАЦИЯ РАБОТАЕТ! Вторая запись обновила первую вместо создания дубликата

   Финальная запись:
   ID: 18
   Content: В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать...
   Tags: ["bugfix", "validation", "unit"] (объединены из обеих записей)
   
SimHash для content1: 4827254215751058630
SimHash для content2: 5944147473094762566
Hamming distance: 6 (максимум для threshold 0.85: 10)
Jaccard similarity: 0.984 (threshold: 0.85)
```

