# frozen_string_literal: true

# Тестовая джоба для проверки работы Sidekiq
class TestJob < BaseSidekiqJob
  sidekiq_options queue: :default, retry: 3

  def perform(message)
    Rails.logger.info "TestJob выполнен: #{message}"
  end
end


