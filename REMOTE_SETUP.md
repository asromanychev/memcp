# Настройка удаленного подключения к MemCP

Инструкция для подключения к memcp с корпоративного ноутбука, когда memcp развернут на другом ноутбуке в той же Wi-Fi сети.

## Архитектура

```
[Серверный ноутбук]                    [Корпоративный ноутбук]
├── Rails API (0.0.0.0:3001)    ←───  ├── Cursor IDE
├── Embedding Server (0.0.0.0:8081)   ├── mcp_server.rb
├── PostgreSQL                          └── MCP конфигурация
└── Sidekiq Worker
```

## Настройка на серверном ноутбуке

### 1. Узнать IP адрес в локальной сети

```bash
# macOS/Linux
ifconfig | grep "inet " | grep -v 127.0.0.1

# или проще
ipconfig getifaddr en0  # macOS (Wi-Fi)
ipconfig getifaddr en1   # macOS (Ethernet)

# Linux
hostname -I | awk '{print $1}'
```

**Пример:** `192.168.1.100` (запомните этот IP)

### 2. Настроить Rails API для удаленного доступа

Puma уже настроен на прослушивание всех интерфейсов (`0.0.0.0`), но можно явно указать:

```bash
# Запуск Rails API на всех интерфейсах
BIND=tcp://0.0.0.0:3001 rails server

# Или через переменную окружения
export BIND=tcp://0.0.0.0:3001
rails server
```

### 3. Запустить Embedding Server

Embedding server уже настроен на прослушивание всех интерфейсов (`0.0.0.0`), просто запустите:

```bash
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server
```

**Важно:** Embedding server будет доступен по IP серверного ноутбука автоматически.

### 4. Настроить firewall (если включен)

**macOS:**
```bash
# Разрешить входящие подключения на порт 3001
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/bin/ruby
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/bin/ruby

# Или через System Preferences:
# System Preferences → Security & Privacy → Firewall → Firewall Options
# Добавить Ruby и разрешить входящие подключения
```

**Linux (ufw):**
```bash
sudo ufw allow 3001/tcp
sudo ufw allow 8081/tcp
```

**Windows:**
- Windows Defender Firewall → Advanced Settings
- Inbound Rules → New Rule
- Port → TCP → 3001, 8081 → Allow

### 5. Запустить все сервисы на серверном ноутбуке

**Терминал 1 - Rails API:**
```bash
cd /path/to/memcp
BIND=tcp://0.0.0.0:3001 rails server
```

**Терминал 2 - Embedding Server:**
```bash
cd /path/to/memcp
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server
```

**Терминал 3 - Sidekiq Worker (опционально):**
```bash
cd /path/to/memcp
bundle exec sidekiq -C config/sidekiq.yml
```

### 6. Проверить доступность с серверного ноутбука

```bash
# Проверка Rails API
curl http://192.168.1.100:3001/up

# Проверка Embedding Server
curl -X POST http://192.168.1.100:8081/embed \
     -H "Content-Type: application/json" \
     -d '{"inputs":["test"]}'
```

## Настройка на корпоративном ноутбуке (клиент)

### 1. Скопировать mcp_server.rb

**Вариант A: Скопировать файл локально**

```bash
# Скопировать mcp_server.rb на корпоративный ноутбук
# Например, в ~/memcp-client/
mkdir -p ~/memcp-client
# Скопируйте файл mcp_server.rb с серверного ноутбука
```

**Вариант B: Использовать общую сетевую папку (если доступна)**

```bash
# Если есть общая папка в сети
# Используйте путь к файлу в общей папке
```

### 2. Узнать IP серверного ноутбука

Спросите у владельца серверного ноутбука или используйте сканер сети:

```bash
# macOS/Linux - сканирование локальной сети
nmap -sn 192.168.1.0/24 | grep -E "Nmap scan report|MAC Address"

# Или просто спросите IP у владельца серверного ноутбука
```

**Пример IP:** `192.168.1.100`

### 3. Настроить Cursor IDE

**Создайте или отредактируйте `~/.cursor/mcp.json`:**

```json
{
  "mcpServers": {
    "memcp": {
      "command": "ruby",
      "args": [
        "/path/to/mcp_server.rb"
      ],
      "env": {
        "MEMCP_API_URL": "http://192.168.1.100:3001"
      }
    }
  }
}
```

**Важно:**
- Замените `/path/to/mcp_server.rb` на реальный путь к файлу на вашем ноутбуке
- Замените `192.168.1.100` на реальный IP серверного ноутбука

### 4. Обновить конфигурацию Embedding Service (если нужно)

Если embedding server тоже должен быть доступен удаленно, обновите переменную окружения:

```bash
# В ~/.cursor/mcp.json можно добавить (но это не обязательно, т.к. embedding server вызывается с сервера)
# Embedding server вызывается Rails API на серверном ноутбуке, поэтому клиенту не нужно к нему подключаться напрямую
```

### 5. Проверить подключение

**С корпоративного ноутбука:**

```bash
# Проверка доступности API
curl http://192.168.1.100:3001/up

# Должен вернуть: {"status":"ok"}
```

### 6. Перезапустить Cursor IDE

Полностью закройте и перезапустите Cursor IDE для применения изменений.

## Проверка работы

### На серверном ноутбуке

```bash
# Проверить логи Rails
tail -f log/development.log

# Проверить, что API слушает на всех интерфейсах
lsof -i :3001
# Должно показать: *:3001 (LISTEN)
```

### На корпоративном ноутбуке

1. Откройте Cursor IDE
2. Попробуйте использовать инструменты `recall` и `save` через чат
3. Проверьте логи Cursor IDE (Developer Tools → Console)

## Troubleshooting

### Проблема: "Connection refused"

**Причина:** Rails API не слушает на всех интерфейсах или firewall блокирует.

**Решение:**
```bash
# На серверном ноутбуке
# 1. Проверить, что Rails запущен с BIND=tcp://0.0.0.0:3001
# 2. Проверить firewall настройки
# 3. Проверить, что порт не занят другим процессом
lsof -i :3001
```

### Проблема: "Timeout" или "Network unreachable"

**Причина:** Ноутбуки не в одной сети или неправильный IP.

**Решение:**
1. Убедитесь, что оба ноутбука в одной Wi-Fi сети
2. Проверьте IP адреса:
   ```bash
   # На серверном ноутбуке
   ifconfig | grep "inet "
   
   # На корпоративном ноутбуке
   ping 192.168.1.100  # замените на IP серверного ноутбука
   ```

### Проблема: CORS ошибки

**Причина:** CORS уже настроен на разрешение всех источников, но если проблемы остаются:

**Решение:** Проверьте `config/initializers/cors.rb` - должно быть `origins "*"`

### Проблема: Embedding generation fails

**Причина:** Embedding server недоступен или не слушает на всех интерфейсах.

**Решение:**
```bash
# На серверном ноутбуке
# Запустить embedding server:
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server

# Проверить доступность:
curl -X POST http://192.168.1.100:8081/embed \
     -H "Content-Type: application/json" \
     -d '{"inputs":["test"]}'
```

## Безопасность

⚠️ **Важно:** Текущая конфигурация разрешает доступ из любой сети. Для production используйте:

1. **Аутентификацию** - добавить API ключи
2. **HTTPS** - использовать SSL/TLS
3. **Firewall правила** - разрешить доступ только с определенных IP
4. **VPN** - использовать VPN для безопасного доступа

Для локальной разработки в одной Wi-Fi сети текущая настройка приемлема.

## Альтернативный вариант: через SSH туннель

Если firewall блокирует прямой доступ, можно использовать SSH туннель:

```bash
# На корпоративном ноутбуке
ssh -L 3001:localhost:3001 user@192.168.1.100

# Затем в Cursor IDE используйте:
# "MEMCP_API_URL": "http://localhost:3001"
```

Это создаст туннель через SSH, и все запросы будут идти через него.
