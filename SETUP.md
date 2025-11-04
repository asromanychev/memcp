# Инструкция по запуску MVP Итерации 1

## Обзор

Это минимально жизнеспособная версия (MVP) архитектуры долгосрочной памяти для AI в IDE. Проект включает:
- **Rails Core API**: API-only приложение для управления памятью
- **Ruby MCP-сервер**: STDIO сервер для интеграции с Cursor IDE

## Требования

- Ruby >= 3.0
- PostgreSQL >= 12 с расширением pgvector
- Rails 8.0.2
- Bundler

## Установка PostgreSQL с pgvector

### Ubuntu/Debian

```bash
# Установка PostgreSQL
sudo apt update
sudo apt install postgresql postgresql-contrib

# Установка pgvector
sudo apt install postgresql-14-pgvector  # или версия для вашей версии PostgreSQL

# Или через исходники:
# git clone --branch v0.5.1 https://github.com/pgvector/pgvector.git
# cd pgvector
# make
# sudo make install
```

### macOS

```bash
brew install postgresql
brew install pgvector
```

## Настройка базы данных

1. Создайте базу данных PostgreSQL:

```bash
# Войдите в PostgreSQL
sudo -u postgres psql

# Создайте базу данных
CREATE DATABASE memcp_development;

# Создайте пользователя (если нужно)
CREATE USER memcp WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE memcp_development TO memcp;

# Выйдите
\q
```

2. Убедитесь, что расширение pgvector доступно:

```bash
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

3. Обновите `config/database.yml` при необходимости (если нужен пароль).

## Установка зависимостей

```bash
cd /home/aromanychev/dev/mcp/memcp
bundle install
```

## Запуск миграций

```bash
rails db:create
rails db:migrate
```

## Запуск Rails Core API

В первом терминале:

```bash
cd /home/aromanychev/dev/mcp/memcp
rails server
```

API будет доступен на `http://localhost:3001`

### Проверка работы API

```bash
# Проверка health check
curl http://localhost:3001/up

# Тест recall (по ТЗ v0.5)
curl -X POST http://localhost:3001/recall \
  -H "Content-Type: application/json" \
  -d '{
    "project_key":"demo",
    "task_external_id":"CS-214",
    "repo_path":"app/services/cart_sessions",
    "symbols":["CartSessions::Setting#trigger_delay_time_in_minutes"],
    "signals":["nil-delay","unit-mismatch"],
    "limit_tokens":2000
  }'

# Тест save (по ТЗ v0.5)
curl -X POST http://localhost:3001/save \
  -H "Content-Type: application/json" \
  -d '{
    "project_key":"demo",
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

## Подключение Ruby MCP-сервера к Cursor IDE

### 1. Настройка в Cursor IDE

1. Откройте настройки Cursor IDE (File > Preferences > Settings или `Cmd/Ctrl + ,`)
2. Найдите раздел "MCP" или "Model Context Protocol"
3. Добавьте новый MCP-сервер:

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": [
        "/home/aromanychev/dev/mcp/memcp/mcp_server.rb"
      ],
      "env": {
        "MEMCP_API_URL": "http://localhost:3001"
      }
    }
  }
}
```

### 2. Альтернативный способ (через конфигурационный файл)

Создайте или отредактируйте файл конфигурации Cursor IDE:

**Linux/macOS**: `~/.cursor/mcp.json` или `~/.config/cursor/mcp.json`
**Windows**: `%APPDATA%\Cursor\mcp.json`

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": [
        "/home/aromanychev/dev/mcp/memcp/mcp_server.rb"
      ],
      "env": {
        "MEMCP_API_URL": "http://localhost:3001"
      }
    }
  }
}
```

### 3. Перезапуск Cursor IDE

После настройки перезапустите Cursor IDE, чтобы подключить MCP-сервер.

## Проверка работы MCP-сервера

### Ручной тест MCP-сервера

```bash
# Запустите сервер вручную для тестирования
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby mcp_server.rb
```

### Проверка через Cursor IDE

1. После подключения MCP-сервера, в Cursor IDE должны быть доступны инструменты:
   - `recall` - поиск воспоминаний
   - `save` - сохранение воспоминаний

2. Попробуйте использовать инструменты через чат в Cursor IDE.

## Структура проекта

```
memcp/
├── app/
│   ├── controllers/
│   │   └── memory_controller.rb    # Контроллер с заглушками recall и save
│   └── models/
│       ├── project.rb               # Модель Project
│       └── memory_record.rb         # Модель MemoryRecord
├── config/
│   ├── routes.rb                    # Маршруты API
│   └── initializers/
│       └── cors.rb                  # CORS настройки
├── db/
│   └── migrate/
│       ├── ..._create_projects.rb           # Миграция projects
│       └── ..._create_memory_records.rb     # Миграция memory_records
├── mcp_server.rb                    # Ruby MCP STDIO сервер
└── Gemfile                          # Зависимости
```

## API Endpoints

### POST /recall

Заглушка для поиска воспоминаний.

**Request:**
```json
{
  "query": "search query",
  "project_path": "/path/to/project"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Recall method called (stub)",
  "query": "search query",
  "project_path": "/path/to/project",
  "results": []
}
```

### POST /save

Заглушка для сохранения воспоминаний.

**Request:**
```json
{
  "content": "content to save",
  "project_path": "/path/to/project",
  "metadata": {}
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Save method called (stub)",
  "payload": {...}
}
```

## MCP Tools

### recall

Поиск воспоминаний по запросу.

**Parameters:**
- `query` (string, required): Поисковый запрос
- `project_path` (string, optional): Путь к проекту

### save

Сохранение записи памяти.

**Parameters:**
- `content` (string, required): Содержимое для сохранения
- `project_path` (string, required): Путь к проекту
- `metadata` (object, optional): Дополнительные метаданные

## Troubleshooting

### Проблема: PostgreSQL не найден

```bash
# Проверьте, запущен ли PostgreSQL
sudo systemctl status postgresql

# Запустите PostgreSQL
sudo systemctl start postgresql
```

### Проблема: Расширение pgvector не найдено

```bash
# Проверьте установку pgvector
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION vector;"

# Если ошибка, установите pgvector через apt или brew
```

### Проблема: MCP-сервер не подключается

1. Проверьте, что Rails API запущен на `http://localhost:3001`
2. Проверьте путь к `mcp_server.rb` в конфигурации Cursor IDE
3. Проверьте права на выполнение: `chmod +x mcp_server.rb`
4. Проверьте логи Cursor IDE

### Проблема: CORS ошибки

Если возникают CORS ошибки, проверьте файл `config/initializers/cors.rb` - для MVP он настроен на разрешение всех источников.

## Следующие шаги (Итерация 2+)

- [ ] Реализация генерации embeddings для сохранения
- [ ] Реализация векторного поиска для recall
- [ ] Добавление аутентификации и авторизации
- [ ] Добавление rate limiting
- [ ] Улучшение обработки ошибок
- [ ] Добавление логирования
- [ ] Тестирование

## Контакты и поддержка

Для вопросов и проблем создайте issue в репозитории проекта.

