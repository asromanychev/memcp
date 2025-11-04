# MemCP - Архитектура Долгосрочной Памяти для AI в IDE

MVP Итерация 1: Минимально жизнеспособная версия архитектуры долгосрочной памяти для AI в IDE.

## Описание

Проект предоставляет архитектуру долгосрочной памяти для AI-ассистентов в IDE (например, Cursor IDE) через MCP (Model Context Protocol). Состоит из:

- **Rails Core API**: API-only приложение для управления памятью (PostgreSQL + pgvector)
- **Ruby MCP-сервер**: STDIO сервер для интеграции с IDE через MCP протокол

## Быстрый старт

### 1. Установка зависимостей

```bash
bundle install
```

### 2. Настройка базы данных

```bash
# Создайте базу данных PostgreSQL
sudo -u postgres psql -c "CREATE DATABASE memcp_development;"
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Запустите миграции
rails db:create
rails db:migrate
```

### 3. Запуск Rails API

```bash
rails server
```

API будет доступен на `http://localhost:3001`

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
