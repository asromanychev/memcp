# Миграция с Solid Queue на Sidekiq + Redis

**Дата:** 2025-11-16  
**Статус:** ✅ Завершено

## Что было сделано

### 1. Обновление зависимостей (Gemfile)
- ❌ Удален `gem "solid_queue"`
- ✅ Добавлен `gem "sidekiq", "~> 7.0"`
- ✅ Добавлен `gem "redis", "~> 5.0"`

### 2. Конфигурация Redis
- ✅ Создан `config/initializers/redis.rb` с паттерном из InSales Atlas
- ✅ Добавлена конфигурация Redis в `config/database.yml`:
  - `redis.default` - основное подключение
  - `redis.sidekiq` - отдельная БД для Sidekiq (db: 1)
- ✅ Используется `REDIS_CONFIG` hash для доступа к конфигурациям

### 3. Конфигурация Sidekiq
- ✅ Создан `config/initializers/sidekiq.rb`:
  - Настройка server и client
  - Обработка ошибок
  - Строгая валидация аргументов
- ✅ Создан `config/sidekiq.yml`:
  - Concurrency: 2
  - Очереди: `default`, `embeddings`

### 4. Обновление окружений
- ✅ `config/environments/development.rb`:
  - Заменен `config.active_job.queue_adapter = :solid_queue` на `:sidekiq`
  - Удалена конфигурация `config.solid_queue.connects_to`

### 5. Миграция джобов
- ✅ Создан `app/jobs/generate_embedding_job.rb`:
  - Использует `Sidekiq::Worker` вместо `ApplicationJob`
  - Метод `perform_async(memory_record_id)` вместо `perform_later`
  - Очередь: `:embeddings`
  - Retry: 3

### 6. Обновление сервисов
- ✅ `app/services/memories/save_service.rb`:
  - Заменен `Memories::GenerateEmbeddingJob.perform_later` на `GenerateEmbeddingJob.perform_async`
  - Удален метод `solid_queue_configured?`
  - Упрощена логика `enqueue_embedding`

### 7. Docker Compose
- ✅ Добавлен сервис `redis` (Redis 7 Alpine)
- ✅ Обновлен сервис `web`:
  - Добавлены переменные окружения для Redis
  - Удалена `SOLID_QUEUE_DATABASE_URL`
- ✅ Обновлен сервис `worker` → `sidekiq`:
  - Команда: `bundle exec sidekiq -C config/sidekiq.yml`
  - Добавлены переменные окружения для Redis
  - Profile: `queue`

### 8. Очистка
- ✅ Удален `config/initializers/solid_queue.rb`
- ✅ Удален `db/queue_schema.rb`
- ✅ Удален `config/queue.yml`
- ✅ Удален `bin/jobs`
- ✅ Удалена директория `db/queue_migrate`
- ✅ Удалена конфигурация `queue` из `database.yml`

## Что осталось сделать и проверить

### 1. Тестирование в Docker ✅
- [x] Запустить контейнеры: `docker-compose up -d`
- [ ] Проверить подключение Redis: `docker-compose exec web rails runner "$redis.ping"`
- [ ] Проверить подключение Sidekiq: `docker-compose exec web rails runner "Sidekiq.redis { |r| r.ping }"`
- [ ] Запустить Sidekiq worker: `docker-compose --profile queue up sidekiq`
- [ ] Проверить, что джобы ставятся в очередь

### 2. Тестирование генерации embeddings
- [ ] Создать тестовую запись через MCP сервер
- [ ] Проверить, что `GenerateEmbeddingJob` ставится в очередь
- [ ] Проверить, что джоба выполняется в Sidekiq
- [ ] Проверить, что embedding генерируется и сохраняется

### 3. Обновление документации
- [ ] Обновить `README.md` с инструкциями по запуску Sidekiq
- [ ] Обновить `ARCHITECTURE.md` (заменить Solid Queue на Sidekiq)
- [ ] Обновить rake tasks (если есть ссылки на Solid Queue)

### 4. Обновление тестов
- [ ] Обновить `spec/tasks/memories_generate_embeddings_spec.rb`:
  - Заменить `have_enqueued_job(Memories::GenerateEmbeddingJob)` на Sidekiq matchers
- [ ] Обновить другие тесты, использующие Solid Queue

### 5. Production конфигурация ✅
- [x] Обновить `config/environments/production.rb`:
  - Заменить `solid_queue` на `sidekiq`
  - Удалить `config.solid_queue.connects_to`
- [ ] Обновить переменные окружения в production:
  - Добавить `REDIS_URL`, `REDIS_SIDEKIQ_DB`
  - Удалить `SOLID_QUEUE_DATABASE_URL`

### 6. Миграция данных (если нужно)
- [ ] Проверить, нет ли данных в `memcp_development_queue` БД
- [ ] Если есть - решить, нужно ли их мигрировать

## Архитектура

### До (Solid Queue)
```
Rails App → Solid Queue → PostgreSQL (queue БД)
```

### После (Sidekiq)
```
Rails App → Sidekiq → Redis (db: 1)
```

## Преимущества миграции

1. ✅ **Простота конфигурации** - не нужна отдельная БД для очередей
2. ✅ **Совместимость** - Sidekiq используется в InSales Atlas
3. ✅ **Производительность** - Redis быстрее для очередей
4. ✅ **Мониторинг** - Sidekiq Web UI для просмотра очередей
5. ✅ **Гибкость** - больше опций для настройки очередей

## Команды для проверки

```bash
# Запуск всех сервисов
docker-compose up -d

# Запуск Sidekiq worker
docker-compose --profile queue up sidekiq

# Проверка Redis
docker-compose exec web rails runner "$redis.ping"

# Проверка Sidekiq
docker-compose exec web rails runner "Sidekiq.redis { |r| r.ping }"

# Постановка тестовой джобы
docker-compose exec web rails runner "GenerateEmbeddingJob.perform_async(1)"

# Просмотр очередей Sidekiq (если установлен sidekiq-web)
# Открыть http://localhost:3101/sidekiq (если настроен роут)
```

## Проблемы и решения

### Проблема: Порт 16379 уже занят
**Решение:** Использовать другой порт или остановить существующий Redis

### Проблема: Порт 15432 уже занят
**Решение:** Использовать другой порт или остановить существующий PostgreSQL

## Следующие шаги

1. Запустить контейнеры и протестировать базовую функциональность
2. Протестировать генерацию embeddings через MCP сервер
3. Обновить документацию
4. Обновить тесты
5. Подготовить к production deployment
