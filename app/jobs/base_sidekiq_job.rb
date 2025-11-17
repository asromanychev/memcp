# frozen_string_literal: true

# Базовый класс для Sidekiq джоб
# По аналогии с Insales, но упрощенная версия
class BaseSidekiqJob
  include Sidekiq::Worker

  # Опционально: для установки таймаута выполнения
  # perform_timeout 10.minutes
end


