require "securerandom"

module Planner
  class SimplePlanner
    include ActiveModelService

    def initialize(params:)
      super()
      @query = params[:query].to_s
      @skill_id = params[:skill_id]
      @skill_params = params[:skill_params] || {}
      @result = {}
      @trace_id = SecureRandom.uuid
    end

    private

    attr_reader :query, :skill_id, :skill_params, :trace_id

    def validate_call
      errors.add(:base, "query is required") if query.blank? && skill_id.blank?
    end

    def perform
      planner_event_id = nil
      skill = nil

      planner_event_id = log_observability_event(
        operation: "planner.start",
        status: "success",
        payload: { query: query.presence, skill_id: skill_id }
      )

      skill = resolve_skill
      unless skill
        log_observability_event(
          parent_id: planner_event_id,
          operation: "planner.skill_missing",
          status: "error",
          error: { message: "no skill matched query" }
        )
        errors.add(:base, "no skill matched query")
        return
      end

      payload = build_parameters(skill)
      log_observability_event(
        parent_id: planner_event_id,
        operation: "planner.skill_selected",
        status: "success",
        entity: skill.id,
        payload: { parameters: payload }
      )

      execution = execute_skill_with_observability(skill, payload, planner_event_id)
      @result = {
        skill_id: skill.id,
        parameters: payload,
        result: execution[:result],
        errors: execution[:errors]
      }

      log_observability_event(
        parent_id: planner_event_id,
        operation: "planner.finish",
        status: execution[:errors].present? ? "error" : "success",
        entity: skill.id,
        extra: {
          error_messages: execution[:errors].presence,
          result_type: execution[:result].class.name
        }
      )
    rescue StandardError => e
      log_observability_event(
        parent_id: planner_event_id,
        operation: "planner.exception",
        status: "error",
        entity: skill&.id,
        error: e
      )
      errors.add(:base, e.message)
    end

    def resolve_skill
      return Skills::Registry.fetch(skill_id) if skill_id.present?

      normalized = query.downcase
      if normalized.include?("atlas") || normalized.include?("adr")
        Skills::Registry.fetch("atlas_search")
      else
        Skills::Registry.fetch("documents_grep")
      end
    end

    def build_parameters(skill)
      return skill_params if skill_params.present?

      case skill.id
      when "atlas_search"
        { query: query }
      when "documents_grep"
        { pattern: Regexp.escape(query) }
      else
        {}
      end
    end

    def execute_skill_with_observability(skill, payload, parent_event_id)
      started_at = Time.current
      execution = nil
      status = "success"
      error = nil

      begin
        execution = skill.callable.call(params: payload)
        status = execution[:errors].present? ? "error" : "success"
        execution
      rescue StandardError => e
        status = "error"
        error = e
        raise
      ensure
        log_observability_event(
          parent_id: parent_event_id,
          operation: "skill.execution",
          status: status,
          entity: skill.id,
          payload: { parameters: payload },
          extra: build_skill_extra(execution),
          error: error,
          started_at: started_at,
          finished_at: Time.current
        )
      end
    end

    def build_skill_extra(execution)
      return {} unless execution

      {
        errors: execution[:errors].presence,
        result_preview: summarize_result(execution[:result])
      }.compact
    end

    def summarize_result(result)
      case result
      when Array
        result.first(3)
      when Hash
        keys = result.keys.first(5)
        result.slice(*keys)
      else
        result
      end
    end

    def log_observability_event(event)
      service = Observability::HubService.call(
        params: {
          event: event.merge(trace_id: trace_id)
        }
      )

      return unless service.success?

      service.result["event_id"]
    rescue StandardError
      nil
    end
  end
end
