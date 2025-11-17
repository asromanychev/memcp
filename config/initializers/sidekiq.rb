# frozen_string_literal: true

# Sidekiq configuration for MemCP
# По аналогии с Insales, но упрощенная версия

# Получаем конфигурацию Redis для Sidekiq
redis_config = REDIS_CONFIG[:sidekiq]

# Конфигурация Sidekiq Server
Sidekiq.configure_server do |config|
  config.redis = redis_config

  # Базовые middleware (упрощенная версия из Insales)
  config.server_middleware do |chain|
    # Добавь свои middleware здесь, если нужно
    # В Insales здесь много middleware, но для memcp можно начать с базовых
  end

  # Basic error handling
  config.error_handlers << proc do |error, context|
    Rails.logger.error("Sidekiq job failed: #{error.class} - #{error.message}")
    Rails.logger.error("Context: #{context}")
  end
end

# Конфигурация Sidekiq Client
Sidekiq.configure_client do |config|
  config.redis = redis_config

  config.client_middleware do |chain|
    # Добавь client middleware здесь, если нужно
  end
end

# Строгая валидация аргументов (из Insales)
Sidekiq.strict_args!(Rails.env.production? ? :warn : :raise)

# Default job options
Sidekiq.default_job_options = {
  retry: 3,
  backtrace: true
}

