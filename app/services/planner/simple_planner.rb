module Planner
  class SimplePlanner
    include ActiveModelService

    def initialize(params:)
      super()
      @query = params[:query].to_s
      @skill_id = params[:skill_id]
      @skill_params = params[:skill_params] || {}
      @result = {}
    end

    private

    attr_reader :query, :skill_id, :skill_params

    def validate_call
      errors.add(:base, "query is required") if query.blank? && skill_id.blank?
    end

    def perform
      skill = resolve_skill
      unless skill
        errors.add(:base, "no skill matched query")
        return
      end

      payload = build_parameters(skill)
      execution = skill.callable.call(params: payload)
      @result = {
        skill_id: skill.id,
        parameters: payload,
        result: execution[:result],
        errors: execution[:errors]
      }
    rescue StandardError => e
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
  end
end

