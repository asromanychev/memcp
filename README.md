# MemCP - Архитектура Долгосрочной Памяти для AI в IDE

MVP Итерация 1: Минимально жизнеспособная версия архитектуры долгосрочной памяти для AI в IDE.

## Описание

Проект предоставляет архитектуру долгосрочной памяти для AI-ассистентов в IDE (например, Cursor IDE) через MCP (Model Context Protocol). Состоит из:

- **Rails Core API**: API-only приложение для управления памятью (PostgreSQL + pgvector)
- **Ruby MCP-сервер**: STDIO сервер для интеграции с IDE через MCP протокол

## Быстрый старт

### Вариант A: Docker (рекомендуется)

Требуется установленный Docker и Docker Compose (плагин `docker compose`).  
Compose-файл использует `dev`-слой Dockerfile, в котором собраны **все** зависимости (включая `development`/`test`).

1. Собрать и запустить все сервисы (Rails API, Solid Queue worker, PostgreSQL + pgvector):
   ```bash
   docker compose up --build
   ```
2. После первого запуска дополнительно ничего делать не нужно — контейнеры выполнят `bundle install`, `rails db:prepare` и подготовку очереди (`db:create:queue`, `db:schema:load:queue`) автоматически.
3. API будет доступен на `http://localhost:3001`, база данных — на `localhost:5432`.

Полезные команды:

- Остановка окружения: `docker compose down`
- Повторная установка gems: `docker compose run --rm web bundle install`
- Запуск тестов: `docker compose run --rm web bundle exec rspec`
- Выполнение разовой команды Rails: `docker compose run --rm web ./bin/rails <command>`
- Подключиться к базе: `docker compose exec db psql -U postgres memcp_development`

> Порты сервисов заданы через ENV и по умолчанию не пересекаются со стандартными значениями:  
> • API: `3101` (`MEMCP_WEB_PORT`)  
> • PostgreSQL: `15432` (`MEMCP_DB_PORT`)  
> При необходимости переопределите их при запуске, например `MEMCP_WEB_PORT=3200 MEMCP_DB_PORT=25432 docker compose up`.

Solid Queue worker по умолчанию не стартует. Запустить его можно так:

```bash
docker compose --profile queue up
```

Перед этим убедитесь, что применены миграции Solid Queue (`rails solid_queue:install && rails db:migrate`).

### Вариант B: Локальная установка

```bash
bundle install

# Создайте базу данных PostgreSQL
sudo -u postgres psql -c "CREATE DATABASE memcp_development;"
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Запустите миграции
rails db:create
rails db:migrate
rails db:create:queue
rails db:schema:load:queue
# Заполнить embeddings для существующих записей (опционально)
rails memories:generate_embeddings

# Запуск Rails API
rails server
```

API также будет доступен на `http://localhost:3001`

### Локальные embeddings (Qwen3 0.6B, Matryoshka 1024d)

- Провайдер по умолчанию: `MEMORY_EMBEDDING_PROVIDER=local_1024`.
- Модель Qwen3-Embedding-0.6B (квантизованная Q8_0) скачивается из репозитория [Qwen/Qwen3-Embedding-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF).  
  Рекомендуемый файл: `Qwen3-Embedding-0.6B-Q8_0.gguf` (≈1.2 ГБ).
- Путь к весам задаётся переменной `MEMORY_EMBEDDING_MODEL_PATH`. По умолчанию используется `tmp/embeddings/Qwen3-Embedding-0.6B-Q8_0.gguf`.
- Для Matryoshka-режима установите `MEMORY_EMBEDDING_OUTPUT_DIM=1024` (значение по умолчанию совпадает со схемой БД).
- Endpoint локального сервиса задаётся `MEMORY_EMBEDDING_ENDPOINT` (по умолчанию `http://127.0.0.1:8081/embed`).
- Для скачивания модели используйте `bin/setup_embeddings` (поддерживает `HF_TOKEN` и проверку SHA256 через `MEMORY_EMBEDDING_MODEL_SHA256`).
- Требования к окружению: `python3` (с поддержкой `venv`), `pip`, `cmake`, компилятор (`build-essential`/`gcc`). Скрипт `bin/embedding_server` создаёт виртуальное окружение `tmp/embedding-venv` и устанавливает зависимости из `embeddings/requirements.txt` (FastAPI, uvicorn, llama-cpp-python).
- Заглушка для OpenAI (`openai_1536`) оставлена для будущего расширения; для неё потребуется `OPENAI_API_KEY`.

### Быстрый старт (локально, включая embeddings)

```bash
bin/setup          # устанавливает зависимости, миграции и очередь (запускает bin/dev автоматически)
```

`bin/dev` запускает Rails и сервис embeddings через `Procfile.dev`. Для ручного запуска служб:

```bash
bin/setup_embeddings        # скачивает веса
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server
bin/rails server
# Solid Queue: запуск воркера в отдельном терминале
# bundle exec rails solid_queue:start
```

Проверка сервиса embeddings:

```bash
curl -X POST http://127.0.0.1:8081/embed \
     -H "Content-Type: application/json" \
     -d '{"inputs":["embedding smoke test"]}'
```
Ответ должен содержать массив `embeddings` длиной 1024.

### Production-образ

Финальный слой Dockerfile — `production`. В нём только runtime-зависимости и включён режим `RAILS_ENV=production`.

```bash
docker build --target production -t memcp:latest .
```

Минимальный пример запуска (потребуются переменные окружения с доступом к базе данных и ключу Rails):

```bash
docker run --rm \
  -e RAILS_ENV=production \
  -e RAILS_MASTER_KEY=<ваш_rails_master_key> \
  -e DATABASE_URL=postgres://user:password@db:5432/memcp_production \
  -p 3001:3001 \
  memcp:latest
```

В production-окружении убедитесь, что база данных содержит расширение `vector`, и выполните миграции:

```bash
docker run --rm \
  -e RAILS_ENV=production \
  -e RAILS_MASTER_KEY=<ваш_rails_master_key> \
  -e DATABASE_URL=postgres://user:password@db:5432/memcp_production \
  memcp:latest \
  bundle exec rails db:migrate
```

> ℹ️ Для production-развёртываний убедитесь, что база данных поддерживает расширение `vector`, и ключ `RAILS_MASTER_KEY` доступен контейнеру.

### Подготовка перед сборкой Docker-образа

Dockerfile содержит только системные зависимости (`python3`, `pip`, `cmake`), поэтому перед сборкой или запуском контейнера разработчику нужно вручную подготовить модель:

```bash
# локально, до docker build
bin/setup_embeddings               # скачивает веса Qwen3 в tmp/embeddings
# опционально проверить сервис
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server &
curl -s http://127.0.0.1:8081/embed \
     -H "Content-Type: application/json" \
     -d '{"inputs":["embedding smoke test"]}' \
     | jq '.embeddings[0] | length'
kill %1   # остановить сервер
```

Затем можно собирать образ (`docker build ...`). Внутри контейнера модель уже лежит в `tmp/embeddings` тома/работающего каталога, и `bin/embedding_server` можно запускать аналогично.

### 4. Настройка MCP-сервера в Cursor IDE

Добавьте в конфигурацию Cursor IDE (`~/.cursor/mcp.json` или через настройки):

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": ["/home/aromanychev/dev/mcp/memcp/mcp_server.rb"],
      "env": {
        "MEMCP_API_URL": "http://localhost:3001"
      }
    }
  }
}
```

Перезапустите Cursor IDE.

## Структура проекта

- `app/controllers/memory_controller.rb` - API контроллер с заглушками `recall` и `save`
- `app/models/` - Модели `Project` и `MemoryRecord`
- `db/migrate/` - Миграции для таблиц `projects` и `memory_records`
- `mcp_server.rb` - Ruby MCP STDIO сервер с инструментами `recall` и `save`

## API Endpoints

- `POST /recall` - Поиск воспоминаний (заглушка)
- `POST /save` - Сохранение воспоминаний (заглушка)

## MCP Tools

- `recall(query, project_path?)` - Поиск воспоминаний по запросу
- `save(content, project_path, metadata?)` - Сохранение записи памяти

## Подробная документация

См. [SETUP.md](SETUP.md) для подробных инструкций по установке и настройке.

## Статус

**MVP Итерация 1** - Заглушки для API и базовый MCP-сервер.

Следующие шаги:
- [ ] Реализация генерации embeddings
- [ ] Реализация векторного поиска
- [ ] Аутентификация и авторизация
- [ ] Тестирование

## Лицензия

MIT
