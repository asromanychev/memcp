# Настройка MemCP на серверном ноутбуке

Эта инструкция описывает полную настройку и запуск MemCP на ноутбуке-сервере для удаленного доступа из других устройств в локальной сети.

## Содержание

1. [Требования](#требования)
2. [Установка зависимостей](#установка-зависимостей)
3. [Настройка базы данных](#настройка-базы-данных)
4. [Настройка проекта](#настройка-проекта)
5. [Настройка для удаленного доступа](#настройка-для-удаленного-доступа)
6. [Запуск сервисов](#запуск-сервисов)
7. [Проверка работы](#проверка-работы)
8. [Troubleshooting](#troubleshooting)

---

## Требования

### Системные требования

- **ОС**: macOS, Linux или Windows (с WSL2)
- **RAM**: минимум 4 ГБ (рекомендуется 8+ ГБ для embeddings)
- **Диск**: минимум 5 ГБ свободного места (для модели embeddings ~1.2 ГБ)

### Программное обеспечение

- **Ruby**: версия 3.2.2 или выше
- **PostgreSQL**: версия 12+ с расширением pgvector
- **Redis**: версия 6+ (для Sidekiq)
- **Python 3**: с поддержкой venv (для embedding server)
- **Bundler**: для управления Ruby зависимостями
- **Git**: для клонирования репозитория

### Дополнительно (для embeddings)

- **cmake**: для сборки llama-cpp-python
- **Компилятор**: gcc/clang (build-essential на Linux)

---

## Установка зависимостей

### macOS

```bash
# Установка Homebrew (если еще не установлен)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Установка зависимостей
brew install postgresql@14 pgvector redis python3 cmake

# Установка Ruby через rbenv (рекомендуется)
brew install rbenv ruby-build
rbenv install 3.2.2
rbenv global 3.2.2

# Или через rvm
curl -sSL https://get.rvm.io | bash -s stable
rvm install 3.2.2
rvm use 3.2.2 --default
```

### Linux (Ubuntu/Debian)

```bash
# Обновление пакетов
sudo apt update

# Установка системных зависимостей
sudo apt install -y \
  postgresql postgresql-contrib \
  postgresql-14-pgvector \
  redis-server \
  python3 python3-pip python3-venv \
  build-essential cmake \
  git curl

# Установка Ruby через rbenv
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
rbenv install 3.2.2
rbenv global 3.2.2
```

### Windows (WSL2)

```bash
# В WSL2 используйте инструкции для Linux (Ubuntu)
# См. раздел выше
```

---

## Настройка базы данных

### 1. Запуск PostgreSQL

**macOS:**
```bash
brew services start postgresql@14
```

**Linux:**
```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql  # автозапуск при загрузке
```

### 2. Создание базы данных

```bash
# Подключение к PostgreSQL
sudo -u postgres psql  # Linux
# или
psql postgres  # macOS (если пользователь postgres существует)

# Создание базы данных
CREATE DATABASE memcp_development;

# Создание расширения pgvector
\c memcp_development
CREATE EXTENSION IF NOT EXISTS vector;

# Выход
\q
```

### 3. Настройка пользователя (опционально)

```bash
# Создание пользователя с паролем
sudo -u postgres psql
CREATE USER memcp WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE memcp_development TO memcp;
\q
```

Если создали пользователя, обновите `config/database.yml`:

```yaml
development:
  primary:
    database: memcp_development
    username: memcp
    password: your_secure_password
```

### 4. Запуск Redis

**macOS:**
```bash
brew services start redis
```

**Linux:**
```bash
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

**Проверка:**
```bash
redis-cli ping
# Должно вернуть: PONG
```

---

## Настройка проекта

### 1. Клонирование репозитория

```bash
cd ~/dev  # или в другую директорию
git clone <repository-url> memcp
cd memcp
```

### 2. Установка Ruby зависимостей

```bash
# Установка Bundler (если еще не установлен)
gem install bundler

# Установка зависимостей проекта
bundle install
```

### 3. Настройка переменных окружения

Создайте файл `.env` в корне проекта (опционально, можно использовать системные переменные):

```bash
# .env
MEMCP_WEB_PORT=3001
MEMCP_DB_PORT=5432
MEMCP_REDIS_PORT=6379
MEMORY_EMBEDDING_PORT=8081
MEMORY_EMBEDDING_PROVIDER=local_1024
```

### 4. Запуск миграций

```bash
# Создание базы данных (если еще не создана)
rails db:create

# Запуск миграций
rails db:migrate

# Создание очередей для Sidekiq
rails db:create:queue
rails db:schema:load:queue
```

### 5. Подготовка модели embeddings

```bash
# Скачивание модели Qwen3-Embedding-0.6B (~1.2 ГБ)
bin/setup_embeddings

# Это создаст:
# - tmp/embeddings/Qwen3-Embedding-0.6B-Q8_0.gguf
# - tmp/embedding-venv/ (виртуальное окружение Python)
```

**Примечание:** Скачивание может занять несколько минут в зависимости от скорости интернета.

---

## Настройка для удаленного доступа

### 1. Узнать IP адрес в локальной сети

**macOS:**
```bash
ipconfig getifaddr en0  # Wi-Fi
ipconfig getifaddr en1  # Ethernet
```

**Linux:**
```bash
hostname -I | awk '{print $1}'
# или
ip addr show | grep "inet " | grep -v 127.0.0.1
```

**Пример результата:** `192.168.1.100` (запомните этот IP)

### 2. Настройка Puma для удаленного доступа

Puma уже настроен на прослушивание всех интерфейсов (`0.0.0.0`), но можно явно указать:

```bash
# При запуске Rails
BIND=tcp://0.0.0.0:3001 rails server
```

### 3. Настройка Firewall

**macOS:**

```bash
# Разрешить входящие подключения для Ruby
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/bin/ruby
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/bin/ruby

# Или через System Preferences:
# System Preferences → Security & Privacy → Firewall → Firewall Options
# Добавить Ruby и разрешить входящие подключения
```

**Linux (ufw):**

```bash
# Разрешить порты
sudo ufw allow 3001/tcp  # Rails API
sudo ufw allow 8081/tcp  # Embedding Server
sudo ufw reload
```

**Linux (firewalld):**

```bash
sudo firewall-cmd --permanent --add-port=3001/tcp
sudo firewall-cmd --permanent --add-port=8081/tcp
sudo firewall-cmd --reload
```

**Windows:**

- Windows Defender Firewall → Advanced Settings
- Inbound Rules → New Rule
- Port → TCP → 3001, 8081 → Allow

---

## Запуск сервисов

MemCP требует запуска нескольких сервисов одновременно. Рекомендуется использовать отдельные терминалы для каждого сервиса.

### Вариант 1: Ручной запуск (для отладки)

**Терминал 1 - Rails API:**
```bash
cd /path/to/memcp
DB_HOST=localhost rails server -b 0.0.0.0 -p 3001
```

**Важно:** Обязательно указывайте `DB_HOST=localhost` для локального запуска (не Docker). Без этого Rails будет пытаться подключиться к хосту `db`, что приведет к зависанию запросов.

**Терминал 2 - Embedding Server:**
```bash
cd /path/to/memcp
MEMORY_EMBEDDING_PORT=8081 bin/embedding_server
```

**Терминал 3 - Sidekiq Worker (опционально):**
```bash
cd /path/to/memcp
DB_HOST=localhost bundle exec sidekiq -C config/sidekiq.yml
```

### Вариант 2: Автоматический запуск (через Procfile.dev)

Если установлен `foreman`:

```bash
# Установка foreman
gem install foreman

# Запуск всех сервисов
bin/dev
```

Или используйте `tmux`/`screen` для управления несколькими терминалами:

```bash
# Установка tmux
brew install tmux  # macOS
sudo apt install tmux  # Linux

# Создание сессии с несколькими окнами
tmux new-session -d -s memcp
tmux send-keys -t memcp:0 "cd /path/to/memcp && DB_HOST=localhost rails server -b 0.0.0.0 -p 3001" C-m
tmux new-window -t memcp
tmux send-keys -t memcp:1 "cd /path/to/memcp && MEMORY_EMBEDDING_PORT=8081 bin/embedding_server" C-m
tmux new-window -t memcp
tmux send-keys -t memcp:2 "cd /path/to/memcp && DB_HOST=localhost bundle exec sidekiq -C config/sidekiq.yml" C-m
tmux attach -t memcp
```

### Вариант 3: Docker (рекомендуется для production)

```bash
# Запуск всех сервисов через Docker Compose
docker compose --profile queue up

# API будет доступен на http://0.0.0.0:3101
```

---

## Проверка работы

### 1. Проверка Rails API

```bash
# С серверного ноутбука
curl http://localhost:3001/up
# Должно вернуть: <!DOCTYPE html><html><body style="background-color: green"></body></html>

# С удаленного устройства (замените IP)
curl http://192.168.1.100:3001/up
# Должно вернуть тот же HTML с зеленым фоном (это нормально для Rails health check)
```

### 2. Проверка Embedding Server

```bash
# С серверного ноутбука
curl -X POST http://localhost:8081/embed \
     -H "Content-Type: application/json" \
     -d '{"inputs":["test embedding"]}'

# С удаленного устройства
curl -X POST http://192.168.1.100:8081/embed \
     -H "Content-Type: application/json" \
     -d '{"inputs":["test embedding"]}'
```

**Ожидаемый результат:** JSON с массивом `embeddings` длиной 1024 чисел.

### 3. Проверка PostgreSQL

```bash
rails dbconsole
# В консоли PostgreSQL:
SELECT COUNT(*) FROM memory_records;
\q
```

### 4. Проверка Redis

```bash
redis-cli ping
# Должно вернуть: PONG

# Проверка Sidekiq очередей
redis-cli -n 1 LLEN queue:embeddings
```

### 5. Проверка портов

**macOS:**
```bash
lsof -i :3001  # Rails API
lsof -i :8081  # Embedding Server
```

**Linux:**
```bash
netstat -tulpn | grep :3001
netstat -tulpn | grep :8081
# или
ss -tulpn | grep :3001
```

Должно показать, что порты слушают на `0.0.0.0` (все интерфейсы).

---

## Troubleshooting

### Проблема: "Connection refused" при подключении с удаленного устройства

**Причины:**
1. Rails API не слушает на всех интерфейсах
2. Firewall блокирует подключения
3. Неправильный IP адрес

**Решение:**
```bash
# 1. Проверить, что Rails запущен с правильными параметрами:
DB_HOST=localhost rails server -b 0.0.0.0 -p 3001

# 2. Проверить, что порт слушает на всех интерфейсах:
ss -tulpn | grep :3001  # Linux
lsof -i :3001  # macOS
# Должно показать: 0.0.0.0:3001 или *:3001 (LISTEN)

# 3. Проверить firewall
# macOS: System Preferences → Security & Privacy → Firewall
# Linux: sudo ufw status

# 4. Проверить IP адрес
ipconfig getifaddr en0  # macOS
hostname -I | awk '{print $1}'  # Linux
```

### Проблема: Запросы доходят до сервера, но нет ответа (зависают)

**Причина:** Rails пытается подключиться к хосту `db` (для Docker) вместо `localhost`.

**Симптомы:**
- В логах видно "Started GET /up", но нет "Completed" или "Processing"
- Запросы зависают и не возвращают ответ
- Health check не отвечает

**Решение:**
```bash
# Обязательно указывайте DB_HOST=localhost при локальном запуске:
DB_HOST=localhost rails server -b 0.0.0.0 -p 3001

# Проверить подключение к БД:
DB_HOST=localhost rails runner "ActiveRecord::Base.connection.execute('SELECT 1')"
```

### Проблема: PostgreSQL не запускается

**Решение:**
```bash
# macOS
brew services restart postgresql@14

# Linux
sudo systemctl status postgresql
sudo systemctl restart postgresql
```

### Проблема: "pgvector extension not found"

**Решение:**
```bash
# Установка pgvector
# macOS
brew install pgvector

# Linux
sudo apt install postgresql-14-pgvector

# Создание расширения в БД
psql -d memcp_development -c "CREATE EXTENSION vector;"
```

### Проблема: Embedding server не запускается

**Причины:**
1. Модель не скачана
2. Python зависимости не установлены
3. Недостаточно памяти

**Решение:**
```bash
# 1. Проверить наличие модели
ls -lh tmp/embeddings/Qwen3-Embedding-0.6B-Q8_0.gguf

# 2. Переустановить зависимости
rm -rf tmp/embedding-venv
bin/setup_embeddings

# 3. Проверить логи
tail -f log/development.log
```

### Проблема: "Redis connection refused"

**Решение:**
```bash
# Запуск Redis
# macOS
brew services start redis

# Linux
sudo systemctl start redis-server

# Проверка
redis-cli ping
```

### Проблема: Sidekiq не обрабатывает задачи

**Решение:**
```bash
# 1. Проверить, что Sidekiq запущен
ps aux | grep sidekiq

# 2. Проверить подключение к Redis
bundle exec rails runner "puts Sidekiq.redis { |c| c.ping }"

# 3. Проверить очереди
bundle exec rails runner "puts Sidekiq::Queue.new('embeddings').size"
```

### Проблема: Медленная работа embeddings

**Причины:**
1. Недостаточно RAM
2. Модель загружается каждый раз

**Решение:**
```bash
# Увеличить количество потоков (если есть свободные CPU ядра)
MEMORY_EMBEDDING_THREADS=8 bin/embedding_server
```

---

## Автозапуск при загрузке системы

### macOS (через launchd)

Создайте файл `~/Library/LaunchAgents/com.memcp.server.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.memcp.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/ruby</string>
    <string>/path/to/memcp/bin/rails</string>
    <string>server</string>
    <string>-b</string>
    <string>0.0.0.0</string>
    <string>-p</string>
    <string>3001</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/path/to/memcp</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
```

Загрузите:
```bash
launchctl load ~/Library/LaunchAgents/com.memcp.server.plist
```

### Linux (через systemd)

Создайте файл `/etc/systemd/system/memcp.service`:

```ini
[Unit]
Description=MemCP Rails API Server
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=your_username
WorkingDirectory=/path/to/memcp
Environment="BIND=tcp://0.0.0.0:3001"
ExecStart=/usr/bin/ruby /path/to/memcp/bin/rails server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Активируйте:
```bash
sudo systemctl daemon-reload
sudo systemctl enable memcp
sudo systemctl start memcp
```

---

## Мониторинг и логи

### Просмотр логов Rails

```bash
tail -f log/development.log
```

### Просмотр логов Sidekiq

```bash
# Если запущен через systemd
sudo journalctl -u sidekiq -f

# Если запущен вручную
# Логи выводятся в консоль
```

### Мониторинг ресурсов

```bash
# Использование памяти
ps aux | grep -E "rails|sidekiq|uvicorn" | awk '{sum+=$6} END {print sum/1024 " MB"}'

# Использование CPU
top -p $(pgrep -f "rails server|sidekiq|uvicorn")
```

---

## Следующие шаги

После успешной настройки серверного ноутбука:

1. **Поделитесь IP адресом** с пользователями, которые будут подключаться
2. **Создайте документацию для клиентов** (см. `REMOTE_SETUP.md`)
3. **Настройте мониторинг** (опционально)
4. **Импортируйте данные** (если нужно):
   ```bash
   rails runner import_aitlas_knowledge.rb
   ```

---

## Полезные команды

```bash
# Остановка всех сервисов
pkill -f "rails server"
pkill -f "sidekiq"
pkill -f "uvicorn"

# Перезапуск базы данных
rails db:drop db:create db:migrate

# Очистка очередей Sidekiq
bundle exec rails runner "Sidekiq::Queue.new('embeddings').clear"

# Генерация embeddings для существующих записей
rails memories:generate_embeddings
```

---

## Поддержка

При возникновении проблем:

1. Проверьте логи: `log/development.log`
2. Проверьте статус сервисов: `ps aux | grep -E "rails|sidekiq|uvicorn"`
3. Проверьте подключения: `lsof -i :3001` и `lsof -i :8081`
4. Обратитесь к документации: `README.md`, `SETUP.md`
