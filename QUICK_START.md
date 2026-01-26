# Быстрый запуск MemCP

Краткая инструкция по запуску MemCP на серверном ноутбуке и подключению с корпоративного ноутбука.

## На серверном ноутбуке

### 1. Проверка базы данных

```bash
# Проверить, что база данных существует
sudo -u postgres psql -lqt | grep memcp_development

# Если нет - создать:
sudo -u postgres psql -c "CREATE DATABASE memcp_development;"
sudo -u postgres psql -d memcp_development -c "CREATE EXTENSION IF NOT EXISTS vector;"
rails db:migrate
```

### 2. Узнать IP адрес

```bash
hostname -I | awk '{print $1}'  # Linux
# или
ipconfig getifaddr en0  # macOS
```

**Запомните этот IP** (например, `192.168.0.93`) - он понадобится для подключения.

### 3. Запустить сервисы

**Терминал 1 - Rails API:**
```bash
cd /path/to/memcp
DB_HOST=localhost rails server -b 0.0.0.0 -p 3001
```

**Терминал 2 - Embedding Server (опционально):**
```bash
cd /path/to/memcp
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server
```

**Терминал 3 - Sidekiq Worker (опционально):**
```bash
cd /path/to/memcp
DB_HOST=localhost bundle exec sidekiq -C config/sidekiq.yml
```

### 4. Проверка

```bash
curl http://localhost:3001/up
# Должно вернуть: <!DOCTYPE html><html><body style="background-color: green"></body></html>
```

## На корпоративном ноутбуке

### 1. Скопировать mcp_server.rb

Скопируйте файл `/path/to/memcp/mcp_server.rb` с серверного ноутбука на корпоративный ноутбук.

### 2. Настроить Cursor IDE

Создайте или отредактируйте `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": [
        "/path/to/mcp_server.rb"
      ],
      "env": {
        "MEMCP_API_URL": "http://192.168.0.93:3001"
      }
    }
  }
}
```

**Важно:**
- Замените `/path/to/mcp_server.rb` на реальный путь к файлу на корпоративном ноутбуке
- Замените `192.168.0.93` на IP адрес серверного ноутбука

### 3. Перезапустить Cursor IDE

Полностью закройте и перезапустите Cursor IDE.

### 4. Проверка

```bash
curl http://192.168.0.93:3001/up
# Должно вернуть: <!DOCTYPE html><html><body style="background-color: green"></body></html>
```

В Cursor IDE должны быть доступны инструменты `recall` и `save`.

## Важные моменты

1. **Обязательно указывайте `DB_HOST=localhost`** при локальном запуске (не Docker)
2. **Rails должен слушать на `0.0.0.0`**, а не только на `localhost`
3. **Оба ноутбука должны быть в одной Wi-Fi сети**
4. **Firewall не должен блокировать порт 3001**

## Troubleshooting

### Запросы зависают без ответа

**Решение:** Убедитесь, что Rails запущен с `DB_HOST=localhost`:
```bash
DB_HOST=localhost rails server -b 0.0.0.0 -p 3001
```

### "Connection refused"

**Решение:** Проверьте, что Rails слушает на всех интерфейсах:
```bash
ss -tulpn | grep :3001  # Linux
# Должно показать: 0.0.0.0:3001
```

### "Method not found: notifications/initialized"

**Решение:** Убедитесь, что используете актуальную версию `mcp_server.rb` с обработкой уведомлений.

## Подробная документация

- [docs/server_setup.md](docs/server_setup.md) - Полная настройка серверного ноутбука
- [REMOTE_SETUP.md](REMOTE_SETUP.md) - Подробная инструкция по удаленному подключению
