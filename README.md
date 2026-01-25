# MemCP - Архитектура Долгосрочной Памяти для AI в IDE

MVP Итерация 1: Минимально жизнеспособная версия архитектуры долгосрочной памяти для AI в IDE.

## Описание

Проект предоставляет архитектуру долгосрочной памяти для AI-ассистентов в IDE (например, Cursor IDE) через MCP (Model Context Protocol). Состоит из:

- **Rails Core API**: API-only приложение для управления памятью (PostgreSQL + pgvector)
- **Sidekiq + Redis**: Асинхронная обработка задач через Sidekiq с использованием Redis
- **Ruby MCP-сервер**: STDIO сервер для интеграции с IDE через MCP протокол

## Быстрый старт

> 📘 **Для проекта Insales:** См. подробную инструкцию [INSTALLATION_INSALES.md](INSTALLATION_INSALES.md) с пошаговыми инструкциями по установке и подключению MCP сервера в Cursor IDE.

### Вариант A: Docker (рекомендуется)

Требуется установленный Docker и Docker Compose (плагин `docker compose`).  
Compose-файл использует `dev`-слой Dockerfile, в котором собраны **все** зависимости (включая `development`/`test`).

1. Собрать и запустить все сервисы (Rails API, PostgreSQL + pgvector, Redis):
   ```bash
   docker compose up --build
   ```
2. После первого запуска дополнительно ничего делать не нужно — контейнеры выполнят `bundle install` и `rails db:prepare` автоматически.
3. API будет доступен на `http://localhost:3101`, база данных — на `localhost:15433`, Redis — на `localhost:16380`.

Полезные команды:

- Остановка окружения: `docker compose down`
- Повторная установка gems: `docker compose run --rm web bundle install`
- Запуск тестов: `docker compose run --rm web bundle exec rspec`
- Выполнение разовой команды Rails: `docker compose run --rm web ./bin/rails <command>`
- Подключиться к базе: `docker compose exec db psql -U postgres memcp_development`
- Подключиться к Redis: `docker compose exec redis redis-cli`
- Просмотр логов Sidekiq: `docker compose logs worker -f`

> Порты сервисов заданы через ENV и по умолчанию не пересекаются со стандартными значениями:  
> • API: `3101` (`MEMCP_WEB_PORT`)  
> • PostgreSQL: `15433` (`MEMCP_DB_PORT`)  
> • Redis: `16380` (`MEMCP_REDIS_PORT`)  
> При необходимости переопределите их при запуске, например `MEMCP_WEB_PORT=3200 MEMCP_DB_PORT=25433 MEMCP_REDIS_PORT=26380 docker compose up`.

### Sidekiq Worker (очереди задач)

Sidekiq worker по умолчанию не стартует. Запустить его можно так:

```bash
docker compose --profile queue up
```

Worker использует Redis для хранения очередей задач. Конфигурация Redis находится в `config/database.yml` (секция `redis:`), отдельные базы данных используются для:
- `default` (db: 0) — общее использование Redis
- `sidekiq` (db: 1) — очереди Sidekiq

Проверка работы Redis и Sidekiq:

```bash
# Проверка Redis
docker compose exec redis redis-cli ping

# Проверка через Rails console
docker compose run --rm web bundle exec rails runner 'puts $redis.ping; puts Sidekiq.redis { |c| c.ping }'

# Постановка тестовой джобы в очередь
docker compose run --rm web bundle exec rails runner 'TestJob.perform_async("test")'
```

### Вариант B: Локальная установка

```bash
bundle install

# Создайте базу данных PostgreSQL
sudo -u postgres psql -c "CREATE DATABASE memcp_development;"
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Запустите миграции
rails db:create
rails db:migrate

# Убедитесь, что Redis запущен локально или через Docker
# Запустите Sidekiq worker (в отдельном терминале)
bundle exec sidekiq -C config/sidekiq.yml

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
# Sidekiq: запуск воркера в отдельном терминале
# bundle exec sidekiq -C config/sidekiq.yml

### Atlas Adapter (зеркалирование insales_atlas)

- Сервис `Atlas::SyncService` копирует документы из `insales_atlas/` в `storage/atlas/`, вычисляет SHA256 и избавляется от дубликатов (один blob на несколько источников).
- Для запуска синхронизации:  
  ```bash
  bundle exec rails atlas:sync
  ```
- Метаданные доступны в `storage/atlas/index.json`, контент — в `storage/atlas/blobs/`.
- Повторный запуск обновляет индекс и копирует только новые/изменённые файлы (по SHA).
- Каталог `storage/` не версионируется: каждый разработчик наполняет его локально (см. `storage/README.md`). При очистке окружения содержимое можно удалять.
```

### File Sync Adapter (локальные документы)

- `FileSync::WatcherService` синхронизирует `documents/` в `storage/documents/`, вычисляет SHA и обновляет индекс.
- Поддерживаются текстовые расширения `.md`, `.mdc`, `.txt`, `.rb`, `.js`, `.sql`, `.json`, `.yml`, `.yaml`.
- Запуск initial sync + watcher:
  ```bash
  bundle exec rails runner 'FileSync::WatcherService.call(params: { source_root: Rails.root.join("documents"), target_root: Rails.root.join("storage/documents") })'
  ```
  (держи процесс в отдельном терминале — `listen` следит за изменениями).
- Метаданные лежат в `storage/documents/index.json`; удаление исходного файла удаляет копию и запись в индексе.
- Краткий smoke:
  ```bash
  echo "# notes" > documents/sample.md
  bundle exec rails runner 'service = FileSync::WatcherService.call(params: { source_root: Rails.root.join("documents"), target_root: Rails.root.join("storage/documents") }); sleep 1'
  cat storage/documents/sample.md
  cat storage/documents/index.json | jq .
  ```
  После проверки останови watcher комбинацией `Ctrl+C`.

### Skills & Planner (MVP)

- Навыки регистрируются через `Skills::Registry`; сейчас доступны:
  - `atlas_search(query:, limit: 10)` — поиск в зеркале `storage/atlas/index.json`.
  - `documents_grep(pattern:, limit: 10)` — текстовый поиск в `storage/documents/`.
- Планировщик `Planner::SimplePlanner` подбирает навык по запросу или принимает `skill_id` явно.
- Примеры:
  ```ruby
  result = Planner::SimplePlanner.call(params: { query: "atlas adr short link" })
  puts result.result[:result][:matches]

  result = Planner::SimplePlanner.call(params: { skill_id: :documents_grep, skill_params: { pattern: "CartSessions" } })
  puts result.result[:result][:matches]
  ```
- Ошибки навыков возвращаются в `result.result[:errors]`.

### Observability Hub (reasoning-логи)

- `Observability::HubService` пишет события планировщика и навыков в `storage/logs/observability/current.jsonl`. Формат записи: JSONL со стандартными полями (`trace_id`, `event_id`, `operation`, `status`, `duration_ms`, `payload`, `extra`, `error`).
- Встроенная ротация: при достижении 10 МБ файл переименовывается в `current.jsonl.<timestamp>.jsonl.gz`, новый файл создаётся автоматически.
- Smoke-сценарий:
  ```bash
  # 1. Подготовить временный источник Atlas
  mkdir -p tmp/atlas_demo/guides
  cat <<'EOF' > tmp/atlas_demo/guides/intro.md
  # Demo Guide
  Demo document for observability smoke.
  EOF

  bundle exec rails runner 'Atlas::SyncService.call(params: { source_root: Rails.root.join("tmp/atlas_demo") })'

  # 2. Вызвать планировщик с явным навыком
  bundle exec rails runner 'Planner::SimplePlanner.call(params: { query: "", skill_id: :atlas_search, skill_params: { query: "demo" } })'

  # 3. Проверить свежие события
  tail -n 5 storage/logs/observability/current.jsonl

  # 4. Очистить временные артефакты (опционально)
  rm -rf tmp/atlas_demo
  ```
- При ошибках навыков `status` сменится на `error`, дополнительный контекст попадёт в `error` и `extra`. Если запись лога не удалась, бизнес-логика продолжит выполнение (исключения подавляются).

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
      "args": ["/Users/asromanychev/dev/memcp/mcp_server.rb"],
      "env": {
        "MEMCP_API_URL": "http://localhost:3101"
      }
    }
  }
}
```

**Важно:**
- Замените путь `/Users/asromanychev/dev/memcp/mcp_server.rb` на ваш реальный путь к файлу
- Убедитесь, что сервер запущен: `docker compose --profile queue up`
- API доступен на `http://localhost:3101` (порт можно изменить через `MEMCP_WEB_PORT`)

Перезапустите Cursor IDE после настройки.

## Структура проекта

- `app/controllers/memory_controller.rb` - API контроллер с заглушками `recall` и `save`
- `app/models/` - Модели `Project` и `MemoryRecord`
- `app/jobs/` - Sidekiq джобы (базовый класс `BaseSidekiqJob`, `GenerateEmbeddingJob`, `TestJob`)
- `db/migrate/` - Миграции для таблиц `projects` и `memory_records`
- `config/database.yml` - Конфигурация PostgreSQL и Redis (секция `redis:`)
- `config/initializers/01_redis.rb` - Инициализация подключения к Redis (`$redis`)
- `config/initializers/sidekiq.rb` - Конфигурация Sidekiq (сервер и клиент)
- `config/sidekiq.yml` - Конфигурация очередей Sidekiq
- `mcp_server.rb` - Ruby MCP STDIO сервер с инструментами `recall` и `save`

## API Endpoints

- `POST /recall` - Поиск воспоминаний (заглушка)
- `POST /save` - Сохранение воспоминаний (заглушка)

## MCP Tools

- `recall(query, project_path?)` - Поиск воспоминаний по запросу
- `save(content, project_path, metadata?)` - Сохранение записи памяти

## Подробная документация

- [SETUP.md](SETUP.md) - подробные инструкции по установке и настройке
- [docs/server_setup.md](docs/server_setup.md) - **настройка серверного ноутбука для удаленного доступа**
- [REMOTE_SETUP.md](REMOTE_SETUP.md) - подключение к удаленному memcp с клиентского устройства

## Статус

**Текущее состояние (2025-11-11):**

✅ **Завершено:**
- MVP-01: Core API Service Objects (`Memories::RecallService`, `Memories::SaveService`)
- MVP-02: Векторный поиск (`Memories::EmbeddingService`, гибридный поиск в `RecallService`, `GenerateEmbeddingJob`)
- **Sidekiq + Redis**: Настройка очередей задач через Sidekiq с использованием Redis (конфигурация по аналогии с Insales, упрощенная версия)
  - Конфигурация Redis в `config/database.yml` с отдельными базами для default (db: 0) и sidekiq (db: 1)
  - Инициализация `$redis` в `config/initializers/01_redis.rb`
  - Конфигурация Sidekiq в `config/initializers/sidekiq.rb`
  - Базовый класс `BaseSidekiqJob` для джоб
- Atlas Adapter (`Atlas::SyncService`) — зеркалирование insales_atlas
- File Sync Adapter (`FileSync::WatcherService`) — синхронизация локальных документов
- Skills & Planner MVP (`Skills::Registry`, `Planner::SimplePlanner`, навыки `atlas_search` и `documents_grep`)
- Observability Hub (базовая реализация: `Observability::HubService`, JSONL-логи с ротацией, интеграция в планировщик)

**Следующие шаги:**

**Этап 2 (текущий):**
- MVP-03: Дедупликация (SimHash/MinHash для обнаружения похожих записей и upsert логика)

**Этап 3 (отложено):**
- Расширить Observability Hub: агрегаты по навыкам, экспорт в Prometheus/ClickHouse, алерты
  - **Когда необходимо:** при реальной нагрузке (десятки запросов/мин), необходимости мониторинга в production, росте команды (нужны дашборды), автоматической диагностике проблем
- Demo Playbooks (resettable сценарии для dev-практик)

## Лицензия

MIT
