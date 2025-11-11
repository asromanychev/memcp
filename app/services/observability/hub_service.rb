require "securerandom"

module Observability
  class HubService
    include ActiveModelService

    DEFAULT_STATUS = "unknown".freeze
    BASE_FIELDS = %i[
      trace_id
      event_id
      parent_id
      timestamp
      operation
      entity
      payload
      error
      status
      duration_ms
      tags
      context
      extra
    ].freeze

    def initialize(params:)
      super()
      @event = params[:event]
      @writer = params[:writer]
      @result = {}
    end

    private

    attr_reader :event

    def validate_call
      unless event.is_a?(Hash)
        errors.add(:base, "event is required")
        return
      end

      operation = event.with_indifferent_access[:operation]
      errors.add(:base, "operation is required") if operation.to_s.blank?
    end

    def perform
      normalized_event = build_event
      writer.write(normalized_event)
      @result = normalized_event
    rescue StandardError => e
      errors.add(:base, e.message)
    end

    def build_event
      event_hash = event.deep_symbolize_keys
      normalized = default_event(event_hash).merge(event_hash.slice(*BASE_FIELDS))
      normalized[:status] ||= DEFAULT_STATUS
      normalized[:duration_ms] = compute_duration(event_hash, normalized[:duration_ms])
      normalized[:error] = normalize_error(normalized[:error])
      extra = event_hash.except(*BASE_FIELDS, :started_at, :finished_at, :error)
      normalized[:extra] = extra if extra.present?
      normalized.compact.transform_keys(&:to_s)
    end

    def default_event(event_hash)
      {
        trace_id: event_hash[:trace_id] || SecureRandom.uuid,
        event_id: event_hash[:event_id] || SecureRandom.uuid,
        parent_id: event_hash[:parent_id],
        timestamp: event_hash[:timestamp] || Time.current.utc.iso8601(6),
        operation: event_hash[:operation].to_s,
        entity: event_hash[:entity],
        payload: event_hash[:payload],
        error: event_hash[:error],
        status: event_hash[:status],
        duration_ms: event_hash[:duration_ms]
      }
    end

    def compute_duration(event_hash, current_value)
      return current_value if current_value

      started_at = event_hash[:started_at]
      finished_at = event_hash[:finished_at]

      start_float = time_to_float(started_at)
      finish_float = time_to_float(finished_at)

      return unless start_float && finish_float

      ((finish_float - start_float) * 1000).round(3)
    end

    def time_to_float(value)
      case value
      when Time
        value.to_f
      when Numeric
        value.to_f
      else
        parsed = Time.zone.parse(value.to_s)
        parsed&.to_f
      end
    end

    def normalize_error(value)
      case value
      when nil
        nil
      when Exception
        {
          class: value.class.name,
          message: value.message,
          backtrace: Array(value.backtrace).first(10)
        }
      when Hash
        value
      else
        { message: value.to_s }
      end
    end

    def writer
      @writer ||= Observability::Adapters::JsonlWriter.new
    end
  end
end
