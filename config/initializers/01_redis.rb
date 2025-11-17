# frozen_string_literal: true

# Инициализация подключения к Redis
# По аналогии с Insales, но упрощенная версия

$redis = Redis.new(REDIS_CONFIG[:default])

# Опционально: логирование в development
if Rails.env.development?
  module GlobalRedisLoggerMiddleware
    def logger
      @logger ||= Rails.logger
    end

    def connect(redis_config)
      logger.debug("  [Redis] Connecting to #{redis_config.host}:#{redis_config.port}")
      super
    end

    def call(command, redis_config)
      logger.debug("  [Redis] #{command.inspect}")
      super
    end
  end
  RedisClient.register(GlobalRedisLoggerMiddleware) if defined?(RedisClient)
end

