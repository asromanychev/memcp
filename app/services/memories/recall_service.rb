module Memories
  class RecallService
    def self.call(params:)
      new(params).call
    end

    attr_reader :errors, :result

    def initialize(params)
      @params = params || {}
      @errors = []
      @result = default_result
    end

    def call
      extract_attributes
      validate!
      return self if errors.any?

      project = find_project

      if project.nil?
        @result = default_result
        return self
      end

      records = fetch_records(project)
      @result = build_result(records)

      self
    end

    def success?
      errors.empty?
    end

    private

    attr_reader :params, :project_key, :task_external_id, :repo_path,
                :query, :symbols, :signals, :limit_tokens

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

    def validate!
      errors << "project_key is required" if project_key.blank?
    end

    def find_project
      Project.find_by(key: project_key)
    end

    def fetch_records(project)
      MemoryRecord.search(
        query: query,
        project: project,
        task_external_id: task_external_id,
        repo_path: repo_path,
        symbols: symbols,
        signals: signals,
        limit: 50
      )
    end

    def build_result(records)
      facts = []
      few_shots = []
      links = []
      total_tokens = 0

      records.each do |record|
        next if record.ttl.present? && record.ttl < Time.current

        case record.kind
        when "fact"
          total_tokens, facts = append_fact(record, total_tokens, facts)
        when "fewshot"
          total_tokens, few_shots = append_few_shot(record, total_tokens, few_shots)
        when "adr_link", "link"
          links << {
            title: record.meta&.dig("title") || record.content[0..100],
            url: record.meta&.dig("url") || "",
            scope: record.scope || []
          }
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
      end

      [ total_tokens, facts ]
    end

    def append_few_shot(record, total_tokens, few_shots)
      token_estimate = record.content.length / 4
      if total_tokens + token_estimate <= limit_tokens && few_shots.length < 3
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
