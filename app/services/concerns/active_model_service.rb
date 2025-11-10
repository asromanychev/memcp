module ActiveModelService
  extend ActiveSupport::Concern

  class InvalidCallError < StandardError; end

  included do
    include ActiveModel::Validations

    attr_reader :result
  end

  class_methods do
    def call(**kwargs)
      service = new(**kwargs)
      service.__send__(:execute)
      service
    end

    def call!(**kwargs)
      service = call(**kwargs)
      raise InvalidCallError, service.errors.full_messages.to_sentence if service.fail?

      service
    end
  end

  def success?
    errors.empty?
  end
  alias_method :success, :success?

  def fail?
    !success?
  end
  alias_method :failure?, :fail?

  private

  def execute
    errors.clear
    validate_call
    return self if fail?

    perform
    self
  rescue ActiveRecord::RecordInvalid => e
    errors.merge!(e.record.errors)
    self
  end

  def validate_call; end

  def perform; end
end

