# Инструкция по установке и подключению MemCP для проекта Insales

## Обзор

Данная инструкция описывает установку и настройку MemCP (MCP сервера долгосрочной памяти) для использования в проекте Insales через Cursor IDE.

## Требования

- Ruby >= 3.0
- PostgreSQL >= 12 с расширением pgvector
- Rails 8.0.2
- Bundler
- Docker и Docker Compose (опционально, для Docker-варианта)
- Python 3 с venv (для локальных embeddings)

## Вариант 1: Установка через Docker (рекомендуется)

### Шаг 1: Клонирование и подготовка

```bash
cd /Users/asromanychev/dev/memcp
```

### Шаг 2: Запуск через Docker Compose

```bash
# Сборка и запуск всех сервисов (Rails API, PostgreSQL + pgvector)
docker compose up --build
```

При первом запуске контейнеры автоматически:
- Выполнят `bundle install`
- Создадут базы данных (`rails db:prepare`)
- Подготовят очередь (`db:create:queue`, `db:schema:load:queue`)

### Шаг 3: Проверка работы API

API будет доступен на `http://localhost:3101` (порт по умолчанию из ENV).

Проверка:
```bash
curl http://localhost:3101/up
```

### Шаг 4: Запуск Solid Queue worker (опционально)

Для обработки фоновых задач (генерация embeddings):

```bash
docker compose --profile queue up
```

### Полезные команды Docker

```bash
# Остановка окружения
docker compose down

# Переустановка gems
docker compose run --rm web bundle install

# Запуск тестов
docker compose run --rm web bundle exec rspec

# Выполнение команды Rails
docker compose run --rm web ./bin/rails <command>

# Подключение к базе данных
docker compose exec db psql -U postgres memcp_development
```

---

## Вариант 2: Локальная установка

### Шаг 1: Установка зависимостей

#### macOS

```bash
# Установка PostgreSQL и pgvector
brew install postgresql
brew install pgvector

# Запуск PostgreSQL
brew services start postgresql
```

#### Ubuntu/Debian

```bash
# Установка PostgreSQL
sudo apt update
sudo apt install postgresql postgresql-contrib

# Установка pgvector
sudo apt install postgresql-14-pgvector  # или версия для вашей PostgreSQL
```

### Шаг 2: Настройка базы данных

```bash
# Создание базы данных
sudo -u postgres psql -c "CREATE DATABASE memcp_development;"

# Создание расширения pgvector
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Опционально: создание пользователя
sudo -u postgres psql -c "CREATE USER memcp WITH PASSWORD 'your_password';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE memcp_development TO memcp;"
```

Если создали пользователя, обновите `config/database.yml`:

```yaml
development:
  primary:
    <<: *default
    database: memcp_development
    username: memcp
    password: your_password
```

### Шаг 3: Установка Ruby зависимостей

```bash
cd /Users/asromanychev/dev/memcp
bundle install
```

### Шаг 4: Запуск миграций

```bash
rails db:create
rails db:migrate
rails db:create:queue
rails db:schema:load:queue
```

### Шаг 5: Настройка локальных embeddings (опционально)

Для использования локальной модели Qwen3-Embedding-0.6B:

```bash
# Скачивание модели (≈1.2 ГБ)
bin/setup_embeddings

# Запуск сервиса embeddings
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server
```

Проверка работы embeddings:
```bash
curl -X POST http://127.0.0.1:8081/embed \
     -H "Content-Type: application/json" \
     -d '{"inputs":["embedding smoke test"]}'
```

### Шаг 6: Запуск Rails API

В отдельном терминале:

```bash
rails server
```

API будет доступен на `http://localhost:3001` (или порт из `MEMCP_WEB_PORT`).

### Шаг 7: Запуск Solid Queue worker (опционально)

В отдельном терминале:

```bash
bundle exec rails solid_queue:start
```

---

## Подключение MCP сервера в Cursor IDE

### Шаг 1: Определение пути к mcp_server.rb

Убедитесь, что знаете полный путь к файлу:
```bash
# Проверка пути
ls -la /Users/asromanychev/dev/memcp/mcp_server.rb
```

### Шаг 2: Настройка конфигурации Cursor IDE

#### Способ A: Через настройки Cursor IDE

1. Откройте настройки Cursor IDE:
   - macOS: `Cmd + ,` или `Cursor > Settings`
   - Windows/Linux: `Ctrl + ,` или `File > Preferences > Settings`

2. Найдите раздел "MCP" или "Model Context Protocol"

3. Добавьте конфигурацию MCP сервера:

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": [
        "/Users/asromanychev/dev/memcp/mcp_server.rb"
      ],
      "env": {
        "MEMCP_API_URL": "http://localhost:3001"
      }
    }
  }
}
```

**Важно:** Если используете Docker, измените `MEMCP_API_URL` на `http://localhost:3101` (порт по умолчанию в Docker).

#### Способ B: Через конфигурационный файл

Создайте или отредактируйте файл конфигурации:

**macOS/Linux:**
```bash
mkdir -p ~/.cursor
nano ~/.cursor/mcp.json
```

**Windows:**
```bash
# Создайте файл: %APPDATA%\Cursor\mcp.json
```

Содержимое файла:

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": [
        "/Users/asromanychev/dev/memcp/mcp_server.rb"
      ],
      "env": {
        "MEMCP_API_URL": "http://localhost:3001"
      }
    }
  }
}
```

**Для Docker-варианта:**

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": [
        "/Users/asromanychev/dev/memcp/mcp_server.rb"
      ],
      "env": {
        "MEMCP_API_URL": "http://localhost:3101"
      }
    }
  }
}
```

### Шаг 3: Проверка прав на выполнение

```bash
chmod +x /Users/asromanychev/dev/memcp/mcp_server.rb
```

### Шаг 4: Перезапуск Cursor IDE

Полностью закройте и перезапустите Cursor IDE для применения изменений.

---

## Использование с проектом Insales

### Важно: project_key для Insales

При использовании инструментов `recall` и `save` в Cursor IDE, **обязательно указывайте `project_key: "insales"**:

**Пример использования recall:**
```json
{
  "project_key": "insales",
  "task_external_id": "CS-214",
  "repo_path": "app/services/cart_sessions",
  "symbols": ["CartSessions::Setting#trigger_delay_time_in_minutes"],
  "signals": ["nil-delay", "unit-mismatch"],
  "limit_tokens": 2000
}
```

**Пример использования save:**
```json
{
  "project_key": "insales",
  "task_external_id": "CS-214",
  "kind": "fact",
  "content": "Причина nil: расхождение delay_unit/trigger_delay_unit",
  "scope": ["cart_sessions", "settings"],
  "tags": ["bugfix", "unit"],
  "quality": {"novelty": 0.74, "dup": 0.06, "usefulness": 0.81},
  "ttl": "2026-06-01T00:00:00Z",
  "meta": {"patch_sha": "abc123", "source_dialog_id": "dlg-1"}
}
```

### Проверка работы MCP сервера

1. После перезапуска Cursor IDE, в чате должны быть доступны инструменты:
   - `recall` - поиск воспоминаний по контексту проекта/задачи
   - `save` - сохранение дистиллированных записей памяти

2. Попробуйте использовать инструменты через чат в Cursor IDE.

### Ручной тест MCP сервера

```bash
# Тест инициализации
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby /Users/asromanychev/dev/memcp/mcp_server.rb

# Тест списка инструментов
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | ruby /Users/asromanychev/dev/memcp/mcp_server.rb
```

---

## Синхронизация Atlas документов (опционально)

Если у вас есть доступ к `insales_atlas/`, можно синхронизировать документацию:

```bash
# Синхронизация документов из insales_atlas в storage/atlas
bundle exec rails atlas:sync
```

Метаданные будут доступны в `storage/atlas/index.json`, контент — в `storage/atlas/blobs/`.

---

## Проверка работы API

### Health check

```bash
curl http://localhost:3001/up
```

### Тест recall

```bash
curl -X POST http://localhost:3001/recall \
  -H "Content-Type: application/json" \
  -d '{
    "project_key":"insales",
    "task_external_id":"CS-214",
    "repo_path":"app/services/cart_sessions",
    "symbols":["CartSessions::Setting#trigger_delay_time_in_minutes"],
    "signals":["nil-delay","unit-mismatch"],
    "limit_tokens":2000
  }'
```

### Тест save

```bash
curl -X POST http://localhost:3001/save \
  -H "Content-Type: application/json" \
  -d '{
    "project_key":"insales",
    "task_external_id":"CS-214",
    "kind":"fact",
    "content":"Причина nil: расхождение delay_unit/trigger_delay_unit",
    "scope":["cart_sessions","settings"],
    "tags":["bugfix","unit"],
    "quality":{"novelty":0.74,"dup":0.06,"usefulness":0.81},
    "ttl":"2026-06-01T00:00:00Z",
    "meta":{"patch_sha":"abc123","source_dialog_id":"dlg-1"}
  }'
```

---

## Troubleshooting

### Проблема: PostgreSQL не найден

**macOS:**
```bash
brew services start postgresql
```

**Linux:**
```bash
sudo systemctl status postgresql
sudo systemctl start postgresql
```

### Проблема: Расширение pgvector не найдено

```bash
# Проверка установки
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION vector;"

# Если ошибка, установите pgvector
# macOS:
brew install pgvector

# Ubuntu/Debian:
sudo apt install postgresql-14-pgvector
```

### Проблема: MCP сервер не подключается

1. **Проверьте, что Rails API запущен:**
   ```bash
   curl http://localhost:3001/up
   # или для Docker:
   curl http://localhost:3101/up
   ```

2. **Проверьте путь к mcp_server.rb:**
   ```bash
   ls -la /Users/asromanychev/dev/memcp/mcp_server.rb
   ```

3. **Проверьте права на выполнение:**
   ```bash
   chmod +x /Users/asromanychev/dev/memcp/mcp_server.rb
   ```

4. **Проверьте переменную окружения MEMCP_API_URL:**
   - Для локальной установки: `http://localhost:3001`
   - Для Docker: `http://localhost:3101`

5. **Проверьте логи Cursor IDE:**
   - Откройте Developer Tools в Cursor IDE
   - Проверьте консоль на наличие ошибок

### Проблема: CORS ошибки

Проверьте файл `config/initializers/cors.rb` — для MVP он настроен на разрешение всех источников. Если проблемы остаются, убедитесь, что Rails API запущен и доступен.

### Проблема: Ruby не найден

Убедитесь, что Ruby установлен и доступен в PATH:

```bash
which ruby
ruby --version
```

Если используете rbenv или rvm, убедитесь, что они инициализированы в вашем shell.

---

## Переменные окружения

### Для локальной установки

- `MEMCP_WEB_PORT` - порт для Rails API (по умолчанию: 3001)
- `MEMCP_DB_PORT` - порт для PostgreSQL (по умолчанию: 5432)
- `MEMORY_EMBEDDING_PROVIDER` - провайдер embeddings (по умолчанию: `local_1024`)
- `MEMORY_EMBEDDING_ENDPOINT` - endpoint для embeddings сервиса (по умолчанию: `http://127.0.0.1:8081/embed`)
- `MEMORY_EMBEDDING_MODEL_PATH` - путь к модели embeddings
- `MEMORY_EMBEDDING_OUTPUT_DIM` - размерность embeddings (по умолчанию: 1024)

### Для Docker

Переменные задаются через `docker-compose.yml` или при запуске:

```bash
MEMCP_WEB_PORT=3200 MEMCP_DB_PORT=25432 docker compose up
```

---

## Следующие шаги

После успешной установки и подключения:

1. **Создайте первый проект Insales** (автоматически создастся при первом `save` с `project_key: "insales"`)
2. **Начните использовать инструменты** `recall` и `save` в Cursor IDE
3. **Синхронизируйте Atlas документы** (если доступны)
4. **Настройте embeddings** для улучшения поиска (опционально)

---

## Дополнительная документация

- [README.md](README.md) - общая документация проекта
- [SETUP.md](SETUP.md) - подробные инструкции по установке
- [ARCHITECTURE.md](ARCHITECTURE.md) - архитектура проекта
- [CONCEPT.md](CONCEPT.md) - концепция и дизайн






