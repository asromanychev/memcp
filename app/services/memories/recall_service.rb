require "set"

module Memories
  class RecallService
    include ActiveModelService

    def initialize(params:)
      super()
      @params = params || {}
      @result = default_result
      extract_attributes
    end

    private

    attr_reader :params, :project_key, :task_external_id, :repo_path,
                :query, :symbols, :signals, :limit_tokens

    def validate_call
      errors.add(:base, "project_key is required") if project_key.blank?
    end

    def perform
      project = find_project
      if project.nil?
        @result = default_result
        return
      end

      records = fetch_records(project)
      Rails.logger.debug("[RecallService] fetch_records returned #{records.count} records")
      @result = build_result(records)
      Rails.logger.debug("[RecallService] build_result returned #{@result[:facts].count} facts, #{@result[:few_shots].count} fewshots")
    end

    def extract_attributes
      @project_key = fetch_param(:project_key).presence
      @task_external_id = fetch_param(:task_external_id).presence
      @repo_path = fetch_param(:repo_path).to_s.presence
      @query = fetch_param(:query).presence
      @symbols = Array(fetch_param(:symbols)).compact_blank
      @signals = Array(fetch_param(:signals)).compact_blank
      @limit_tokens = fetch_param(:limit_tokens).to_i
      @limit_tokens = 2000 if @limit_tokens <= 0
    end

    def find_project
      Project.find_by(key: project_key)
    end

    def fetch_records(project)
      text_records = MemoryRecord.search(
        query: query,
        project: project,
        task_external_id: task_external_id,
        repo_path: repo_path,
        symbols: symbols,
        signals: signals,
        limit: 50
      ).to_a

      return text_records if query.blank?

      query_embedding = generate_query_embedding
      return text_records if query_embedding.blank?

      vector_records = fetch_vector_records(project, query_embedding)
      merge_records(vector_records, text_records)
    end

    def build_result(records)
      facts = []
      few_shots = []
      links = []
      total_tokens = 0

      Rails.logger.info("[RecallService] build_result called with #{records.count} records, limit_tokens=#{limit_tokens}")

      # Сортируем записи: сначала pattern/gotcha/rule (более важные), потом fewshot, потом fact
      sorted_records = records.sort_by do |record|
        priority = case record.kind
        when "pattern", "gotcha", "rule"
          0 # Высший приоритет
        when "fewshot"
          1
        when "fact"
          2
        else
          Rails.logger.warn("[RecallService] Unknown kind in sort: #{record.kind.inspect} for record #{record.id}")
          3
        end
        priority
      end
      
      Rails.logger.info("[RecallService] Sorted #{sorted_records.count} records, first 3 kinds: #{sorted_records.first(3).map { |r| "#{r.id}(#{r.kind})" }.join(', ')}")
      
      sorted_records.each do |record|
        if record.ttl.present? && record.ttl < Time.current
          Rails.logger.debug("[RecallService] Skipping expired record #{record.id}")
          next
        end

        Rails.logger.info("[RecallService] Processing record #{record.id}: kind=#{record.kind.inspect}")

        case record.kind
        when "fact"
          result_tuple = append_fact(record, total_tokens, facts)
          total_tokens = result_tuple[0]
          facts = result_tuple[1]
        when "fewshot"
          result_tuple = append_few_shot(record, total_tokens, few_shots)
          total_tokens = result_tuple[0]
          few_shots = result_tuple[1]
        when "pattern", "gotcha", "rule"
          # Pattern, gotcha, rule обрабатываются как facts с высоким приоритетом
          result_tuple = append_fact(record, total_tokens, facts)
          total_tokens = result_tuple[0]
          facts = result_tuple[1]
          Rails.logger.info("[RecallService] Processing #{record.kind} #{record.id}: facts.count=#{facts.count}, tokens: #{total_tokens}")
        when "adr_link", "link"
          links << {
            title: record.meta&.dig("title") || record.content[0..100],
            url: record.meta&.dig("url") || "",
            scope: record.scope || []
          }
        else
          Rails.logger.warn("[RecallService] Unknown kind for record #{record.id}: #{record.kind.inspect}")
        end

        break if total_tokens >= limit_tokens
      end

      confidence = if records.any?
                     [ (records.count.to_f / 10.0).clamp(0.0, 1.0), 0.5 ].max
      else
                     0.0
      end

      {
        facts: facts,
        few_shots: few_shots,
        links: links,
        confidence: confidence
      }
    end

    def append_fact(record, total_tokens, facts)
      token_estimate = record.content.length / 4
      
      if total_tokens + token_estimate <= limit_tokens
        facts << {
          text: record.content,
          scope: record.scope || [],
          tags: record.tags || []
        }
        total_tokens += token_estimate
        Rails.logger.debug("[RecallService] append_fact: added #{record.kind} #{record.id}, tokens: #{total_tokens}/#{limit_tokens}")
      else
        Rails.logger.debug("[RecallService] append_fact: skipped #{record.kind} #{record.id}, tokens would exceed limit: #{total_tokens + token_estimate}/#{limit_tokens}")
      end

      [ total_tokens, facts ]
    end

    def append_few_shot(record, total_tokens, few_shots)
      token_estimate = record.content.length / 4
      # Увеличиваем лимит fewshots до 5, чтобы не ограничивать результаты
      if total_tokens + token_estimate <= limit_tokens && few_shots.length < 5
        few_shots << {
          title: record.meta&.dig("title") || "Few-shot #{record.id}",
          steps: record.content.split("\n").reject(&:empty?),
          patch_ref: record.meta&.dig("patch_sha"),
          tags: record.tags || []
        }
        total_tokens += token_estimate
      end

      [ total_tokens, few_shots ]
    end

    def fetch_param(key)
      params[key] || params[key.to_s]
    end

    def generate_query_embedding
      service = Memories::EmbeddingService.call(params: { content: query })
      return service.result if service.success?

      Rails.logger.warn(
        "[Memories::RecallService] embedding generation failed: #{service.errors.full_messages.join(', ')}"
      )
      nil
    end

    def fetch_vector_records(project, query_embedding)
      MemoryRecord
        .active
        .for_project(project.id)
        .where.not(embedding_1024: nil)
        .nearest_neighbors(:embedding_1024, query_embedding)
        .limit(30)
    rescue StandardError => e
      Rails.logger.warn("[Memories::RecallService] vector search failed: #{e.message}")
      []
    end

    def merge_records(vector_records, text_records)
      merged = []
      seen_ids = Set.new

      vector_records.each do |record|
        next if seen_ids.include?(record.id)

        merged << record
        seen_ids << record.id
      end

      text_records.each do |record|
        next if seen_ids.include?(record.id)

        merged << record
        seen_ids << record.id
      end

      merged
    end

    def default_result
      {
        facts: [],
        few_shots: [],
        links: [],
        confidence: 0.0
      }
    end
  end
end
