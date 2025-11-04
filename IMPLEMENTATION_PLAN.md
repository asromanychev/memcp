# План реализации MVP Итерации 1

## Выполненные задачи

### ✅ 1. Инициализация Rails API-only проекта
- Создан Rails API-only проект с флагом `--api`
- Настроена базовая структура проекта

### ✅ 2. Настройка зависимостей
- Добавлен `pg` gem для PostgreSQL
- Добавлен `neighbor` gem для работы с pgvector
- Добавлен `rack-cors` для CORS поддержки
- Все зависимости установлены через `bundle install`

### ✅ 3. Миграции базы данных
- Создана миграция `CreateProjects`:
  - `name` (string, not null)
  - `path` (string, not null, unique index)
  - `timestamps`
- Создана миграция `CreateMemoryRecords`:
  - `project_id` (foreign key к projects)
  - `content` (text, not null)
  - `embedding` (vector, dimension 1536)
  - `metadata` (jsonb, default {})
  - `timestamps`
  - Индексы: project_id, metadata (GIN), embedding (IVFFlat)

### ✅ 4. Модели
- `Project` модель:
  - Валидации для `name` и `path`
  - Связь `has_many :memory_records`
- `MemoryRecord` модель:
  - Валидации для `content` и `project_id`
  - Связь `belongs_to :project`
  - Поддержка `has_neighbors :embedding` для векторного поиска

### ✅ 5. Контроллер и маршруты
- `MemoryController` с двумя действиями:
  - `recall` - заглушка для поиска воспоминаний
  - `save` - заглушка для сохранения воспоминаний
- Маршруты:
  - `POST /recall`
  - `POST /save`
- Настроен CORS для локальных запросов

### ✅ 6. Ruby MCP-сервер
- Создан `mcp_server.rb` - STDIO MCP-сервер
- Реализован протокол JSON-RPC для MCP
- Два инструмента:
  - `recall` - вызывает `POST /recall` Rails API
  - `save` - вызывает `POST /save` Rails API
- Обработка методов:
  - `initialize` - инициализация сервера
  - `tools/list` - список доступных инструментов
  - `tools/call` - вызов инструментов

### ✅ 7. Документация
- `README.md` - краткое описание проекта
- `SETUP.md` - подробные инструкции по установке и настройке
- `IMPLEMENTATION_PLAN.md` - этот файл

## Структура проекта

```
memcp/
├── app/
│   ├── controllers/
│   │   └── memory_controller.rb    # API контроллер
│   └── models/
│       ├── project.rb               # Модель Project
│       └── memory_record.rb         # Модель MemoryRecord
├── config/
│   ├── routes.rb                    # Маршруты API
│   └── initializers/
│       └── cors.rb                  # CORS настройки
├── db/
│   └── migrate/
│       ├── 20251104062457_create_projects.rb
│       └── 20251104062500_create_memory_records.rb
├── mcp_server.rb                    # Ruby MCP STDIO сервер
├── Gemfile                          # Зависимости
├── README.md                        # Краткое описание
├── SETUP.md                         # Подробные инструкции
└── IMPLEMENTATION_PLAN.md           # Этот файл
```

## Следующие шаги (Итерация 2+)

### Планируемые улучшения

1. **Генерация embeddings**
   - Интеграция с OpenAI API для генерации embeddings
   - Фоновая обработка при сохранении записей

2. **Векторный поиск**
   - Реализация поиска по векторным embeddings
   - Косинусное расстояние для поиска похожих записей

3. **Аутентификация и авторизация**
   - API ключи или токены
   - Изоляция данных по пользователям/проектам

4. **Обработка ошибок**
   - Улучшенная обработка ошибок в API
   - Логирование

5. **Тестирование**
   - Unit тесты для моделей
   - Integration тесты для API
   - Тесты для MCP-сервера

6. **Оптимизация**
   - Кэширование частых запросов
   - Оптимизация индексов
   - Rate limiting

## Технические детали

### Используемые технологии
- **Rails 8.0.2** - API-only приложение
- **PostgreSQL** - основная база данных
- **pgvector** - расширение для векторных операций
- **neighbor gem** - Ruby обертка для pgvector
- **Ruby** - для MCP-сервера (STDIO)

### API Endpoints

#### POST /recall
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

#### POST /save
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

### MCP Tools

#### recall
Поиск воспоминаний по запросу.

**Parameters:**
- `query` (string, required): Поисковый запрос
- `project_path` (string, optional): Путь к проекту

#### save
Сохранение записи памяти.

**Parameters:**
- `content` (string, required): Содержимое для сохранения
- `project_path` (string, required): Путь к проекту
- `metadata` (object, optional): Дополнительные метаданные

## Запуск проекта

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

### 4. Настройка MCP-сервера в Cursor IDE
Добавьте в конфигурацию Cursor IDE:

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

## Статус реализации

✅ **MVP Итерация 1 завершена**

Все задачи выполнены:
- ✅ Rails API-only проект инициализирован
- ✅ Зависимости настроены
- ✅ Миграции созданы
- ✅ Модели созданы
- ✅ Контроллер с заглушками реализован
- ✅ Ruby MCP-сервер создан
- ✅ Документация написана

Проект готов к использованию для MVP Итерации 1.

