# frozen_string_literal: true

# Скрипт для импорта знаний из aitlas/insales в MCP сервер
require 'fileutils'

# Путь должен быть доступен из контейнера
# Если aitlas не смонтирован, используем путь хоста через volume
AITLAS_PATH = ENV['AITLAS_PATH'] || "/Users/asromanychev/dev/insales/aitlas/insales"
PROJECT_KEY = "insales"

# Проверяем доступность пути
$aitlas_path = AITLAS_PATH
unless Dir.exist?($aitlas_path)
  puts "❌ Директория не найдена: #{$aitlas_path}"
  puts "Попробуем альтернативные пути..."
  # Альтернативные пути
  alt_paths = [
    "/Users/asromanychev/dev/insales/aitlas/insales",
    "/mnt/aitlas/aitlas/insales",
    "/app/../insales/aitlas/insales"
  ]

  found = false
  alt_paths.each do |path|
    if Dir.exist?(path)
      $aitlas_path = path
      found = true
      puts "✅ Найден путь: #{path}"
      break
    end
  end

  unless found
    puts "Убедитесь, что путь доступен или установите AITLAS_PATH"
    exit 1
  end
end

def determine_kind(file_path, content)
  case file_path
  when /cursor\/rules\/.*\.mdc$/
    "rule"
  when /security\//
    "gotcha"
  when /dialogue_reports\//
    "fewshot"
  when /code_reviews\//
    "fewshot"
  when /performance\//
    "pattern"
  when /multiwarehouses\//
    "pattern"
  when /features\//
    # Анализируем содержимое для определения типа
    if content.match?(/уязвимость|vulnerability|security|безопасность/i)
      "gotcha"
    elsif content.match?(/паттерн|pattern|архитектура|architecture/i)
      "pattern"
    else
      "fact"
    end
  when /conventions\//
    "rule"
  when /interview\//
    "fact"
  else
    "fact"
  end
end

def extract_tags(file_path, content)
  tags = []

  # Теги из пути
  tags << "security" if file_path.include?("security")
  tags << "performance" if file_path.include?("performance")
  tags << "redis" if file_path.include?("redis") || content.match?(/redis/i)
  tags << "infrastructure" if file_path.include?("infrastructure") || content.match?(/infrastructure|infra/i)
  tags << "n+1" if content.match?(/n\+1|n plus one/i)
  tags << "optimization" if content.match?(/optimization|оптимизация/i)
  tags << "idor" if content.match?(/idor|межаккаунтн/i)
  tags << "rails" if content.match?(/rails|ruby/i)
  tags << "sidekiq" if content.match?(/sidekiq/i)
  tags << "elasticsearch" if content.match?(/elasticsearch|elastic/i)

  # Извлечение ID задачи из заголовка (например, [ZK72], [BV71])
  if match = content.match(/\[([A-Z0-9]+)\]/)
    tags << match[1].downcase
  end

  tags.uniq.compact
end

def extract_scope(file_path)
  scope = []

  # Извлекаем scope из пути
  parts = file_path.split("/")
  insales_idx = parts.index("insales")

  if insales_idx
    # Берем части пути после insales
    relevant_parts = parts[(insales_idx + 1)..-2] # -2 чтобы исключить имя файла
    scope = relevant_parts.map(&:downcase).reject(&:empty?)
  end

  scope
end

def extract_meta(file_path, content)
  meta = {}

  # Извлечение заголовка
  if match = content.match(/^#\s+(.+)$/)
    meta["title"] = match[1].strip
  end

  # Извлечение ID задачи
  if match = content.match(/\[([A-Z0-9]+)\]/)
    meta["task_id"] = match[1]
  end

  meta
end

def import_file(file_path)
  relative_path = file_path.sub($aitlas_path + "/", "")
  content = File.read(file_path)

  kind = determine_kind(file_path, content)
  tags = extract_tags(file_path, content)
  scope = extract_scope(file_path)
  meta = extract_meta(file_path, content)

  # Сохраняем через Memories::SaveService
  service = Memories::SaveService.call(
    params: {
      project_key: PROJECT_KEY,
      kind: kind,
      content: content,
      scope: scope,
      tags: tags,
      meta: meta
    }
  )

  if service.success?
    puts "✅ #{relative_path} -> #{kind} (tags: #{tags.join(', ')})"
    true
  else
    puts "❌ #{relative_path}: #{service.errors.full_messages.join(', ')}"
    false
  end
rescue => e
  puts "❌ #{relative_path}: #{e.message}"
  false
end

def find_markdown_files(base_path)
  files = []

  Dir.glob("#{base_path}/**/*.{md,mdc}").each do |file|
    # Пропускаем README и некоторые служебные файлы
    next if file.include?("README.md")
    next if file.include?("/.git/")

    files << file
  end

  files
end

# Основной процесс импорта
puts "=" * 80
puts "ИМПОРТ ЗНАНИЙ ИЗ AITLAS/INSALES"
puts "=" * 80
puts

files = find_markdown_files($aitlas_path)
puts "Найдено файлов: #{files.count}"
puts

success_count = 0
error_count = 0

files.each_with_index do |file, index|
  print "[#{index + 1}/#{files.count}] "
  if import_file(file)
    success_count += 1
  else
    error_count += 1
  end
end

puts
puts "=" * 80
puts "РЕЗУЛЬТАТЫ ИМПОРТА"
puts "=" * 80
puts "Успешно: #{success_count}"
puts "Ошибок: #{error_count}"
puts "Всего: #{files.count}"
