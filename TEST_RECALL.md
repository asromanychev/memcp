# Тестирование Recall API

Примеры запросов для проверки работы recall с embeddings на корпоративном ноутбуке.

## 1. Поиск по текстовому запросу (использует векторный поиск)

```bash
curl -X POST http://192.168.0.93:3001/recall \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "insales",
    "query": "sidekiq redis",
    "limit_tokens": 1000
  }'
```

**Ожидаемый результат:** JSON с массивом `facts`, `few_shots`, `links` и `confidence`.

## 2. Поиск по конкретной задаче

```bash
curl -X POST http://192.168.0.93:3001/recall \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "insales",
    "task_external_id": "ZT41",
    "limit_tokens": 500
  }'
```

## 3. Поиск по тегам и символам

```bash
curl -X POST http://192.168.0.93:3001/recall \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "insales",
    "tags": ["redis", "sidekiq"],
    "limit_tokens": 1000
  }'
```

## 4. Комбинированный поиск (векторный + фильтры)

```bash
curl -X POST http://192.168.0.93:3001/recall \
  -H "Content-Type: application/json" \
  -d '{
    "project_key": "insales",
    "query": "оптимизация производительности",
    "repo_path": "features",
    "limit_tokens": 2000
  }'
```

## Проверка наличия embeddings

Если embeddings еще не сгенерированы, векторный поиск не будет работать. Проверьте через Rails console на серверном ноутбуке:

```bash
DB_HOST=localhost rails console

# Проверить количество записей с embeddings
MemoryRecord.where.not(embedding_1024: nil).count

# Проверить конкретную запись
record = MemoryRecord.first
record.embedding_1024.present?  # должно быть true
```

## Генерация embeddings для существующих записей

Если embeddings не сгенерированы, запустите на серверном ноутбуке:

```bash
DB_HOST=localhost rails memories:generate_embeddings
```

Это поставит задачи в очередь Sidekiq для генерации embeddings.
