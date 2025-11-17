# Проблема: MemCP недоступен в development (нужна queue БД)

## Описание проблемы

При попытке сохранить знания через MCP сервер возникает ошибка:
```
MemCP недоступен в development (нужна queue БД)
ActiveRecord::AdapterNotSpecified (The `queue` database is not configured for the `development` environment.)
```

## Корневая причина

1. **Rails не видит конфигурацию `queue` в `database.yml`**
   - База данных `memcp_development_queue` существует
   - Схема применена (`db/queue_schema.rb`)
   - Переменная окружения `SOLID_QUEUE_DATABASE_URL` установлена
   - Но Rails не может найти конфигурацию `queue` для development окружения при использовании `connects_to`

2. **Solid Queue требует конфигурацию из `database.yml`**
   - `config.solid_queue.connects_to = { database: { writing: :queue } }` ожидает, что Rails видит конфигурацию `queue` в `database.yml`
   - При использовании `DATABASE_URL` Rails может игнорировать вложенные конфигурации в `database.yml`

3. **Ошибка возникает при инициализации ActiveJob**
   - Ошибка происходит ДО вызова `perform_later`
   - Даже если добавить проверку и не вызывать `enqueue_embedding`, ошибка все еще возникает

## Что было испробовано

### 1. Исправление конфигурации `database.yml`
- Изменена структура конфигурации `queue` (убрана зависимость от `primary_development`)
- **Результат**: Не помогло, Rails все еще не видит конфигурацию

### 2. Использование `SOLID_QUEUE_DATABASE_URL` напрямую
- Создан initializer для Solid Queue
- Попытка использовать переменную окружения напрямую
- **Результат**: Не помогло, Solid Queue все еще требует конфигурацию из `database.yml`

### 3. Изменение queue adapter на `:async`
- В `config/environments/development.rb` добавлена проверка и переключение на `:async` adapter
- **Результат**: Не помогло, Rails все еще использует `solid_queue` (возможно, кеш конфигурации)

### 4. Вынос `enqueue_embedding` за пределы транзакции
- Изменена структура метода `perform` для вызова `enqueue_embedding` после транзакции
- **Результат**: Не помогло, ошибка все еще вызывает ROLLBACK

### 5. Добавление проверки и пропуск генерации embeddings
- Добавлена проверка `if saved_record && !Rails.env.development?`
- **Результат**: Ошибка все еще возникает (возможно, из-за кеша или другой причины)

## Пути решения

### Решение 1: Исправить конфигурацию `database.yml` (РЕКОМЕНДУЕТСЯ)

**Проблема**: Rails не видит конфигурацию `queue` когда используется `DATABASE_URL`.

**Решение**: Использовать явную конфигурацию в `database.yml` без зависимости от `DATABASE_URL`:

```yaml
development:
  primary:
    <<: *default
    database: memcp_development
    url: <%= ENV.fetch("DATABASE_URL", "postgres://postgres:postgres@localhost:25432/memcp_development") %>
  queue:
    <<: *default
    database: memcp_development_queue
    url: <%= ENV.fetch("SOLID_QUEUE_DATABASE_URL", "postgres://postgres:postgres@localhost:25432/memcp_development_queue") %>
    migrations_paths: db/queue_migrate
```

**Действия**:
1. Обновить `config/database.yml` с явными URL для `queue`
2. Убедиться, что `config/environments/development.rb` использует `solid_queue` с `connects_to`
3. Перезапустить контейнеры

### Решение 2: Использовать async adapter для development (ВРЕМЕННОЕ)

**Проблема**: Solid Queue требует отдельную БД, которая может быть не настроена в development.

**Решение**: Использовать `:async` adapter для development, который не требует отдельной БД:

```ruby
# config/environments/development.rb
config.active_job.queue_adapter = :async
```

**Действия**:
1. Убрать `config.solid_queue.connects_to` из `development.rb`
2. Установить `config.active_job.queue_adapter = :async`
3. Перезапустить контейнеры
4. **Ограничение**: Задачи выполняются в памяти, теряются при перезапуске

### Решение 3: Полностью отключить генерацию embeddings в development (ОБХОДНОЙ ПУТЬ)

**Проблема**: Генерация embeddings требует queue БД.

**Решение**: Пропускать генерацию embeddings в development, генерировать позже через rake task:

```ruby
# app/services/memories/save_service.rb
def perform
  # ... сохранение записи ...
  
  # В development пропускаем генерацию embeddings
  if saved_record && !Rails.env.development?
    enqueue_embedding(saved_record)
  elsif Rails.env.development?
    Rails.logger.info("Development: пропускаем генерацию embedding. Используйте 'rails memories:generate_embeddings' для генерации позже.")
  end
end
```

**Действия**:
1. Убедиться, что проверка `!Rails.env.development?` работает
2. Добавить rake task для генерации embeddings позже
3. **Ограничение**: Embeddings не генерируются автоматически

### Решение 4: Исправить конфигурацию через initializer (АЛЬТЕРНАТИВНОЕ)

**Проблема**: Rails не видит конфигурацию `queue` при использовании `DATABASE_URL`.

**Решение**: Создать initializer, который явно устанавливает подключение для Solid Queue:

```ruby
# config/initializers/solid_queue.rb
if Rails.env.development? && ENV['SOLID_QUEUE_DATABASE_URL'].present?
  Rails.application.config.after_initialize do
    # Устанавливаем подключение напрямую
    SolidQueue::Job.establish_connection(ENV['SOLID_QUEUE_DATABASE_URL'])
  end
end
```

**Действия**:
1. Создать/обновить `config/initializers/solid_queue.rb`
2. Убрать `connects_to` из `development.rb` или оставить
3. Перезапустить контейнеры

## Рекомендации

1. **Краткосрочное решение**: Использовать Решение 3 (отключить генерацию embeddings в development)
2. **Долгосрочное решение**: Исправить конфигурацию `database.yml` (Решение 1) или использовать async adapter (Решение 2)

## Текущий статус

- ✅ База данных `memcp_development_queue` создана
- ✅ Схема применена
- ✅ Переменная окружения `SOLID_QUEUE_DATABASE_URL` установлена
- ❌ Rails не видит конфигурацию `queue` в `database.yml`
- ❌ Ошибка все еще возникает при попытке сохранить знания

## Следующие шаги

1. Попробовать Решение 1 (исправить `database.yml`)
2. Если не поможет, использовать Решение 2 (async adapter)
3. Если и это не поможет, использовать Решение 3 (отключить генерацию embeddings)

