# frozen_string_literal: true

class Memories::RecallService
  def self.call(params:)
    new(params).call
  end

  def initialize(params)
    @project_key = params[:project_key] || params["project_key"]
    @task_external_id = params[:task_external_id] || params["task_external_id"]
    @repo_path = params[:repo_path] || params["repo_path"]
    @symbols = params[:symbols] || params["symbols"] || []
    @signals = params[:signals] || params["signals"] || []
    @limit_tokens = (params[:limit_tokens] || params["limit_tokens"] || 2000).to_i
    @errors = []
  end

  def call
    return self unless valid?

    @result = build_result
    self
  end

  def success?
    @errors.empty?
  end

  def errors
    @errors
  end

  def result
    @result || {}
  end

  private

  def valid?
    if @project_key.blank?
      @errors << "project_key is required"
      return false
    end
    true
  end

  def build_result
    project = Project.find_by(key: @project_key)
    return empty_result unless project

    search_query = build_search_query
    records = search_records(project, search_query)

    build_bundle(records)
  end

  def build_search_query
    query_parts = []
    query_parts.concat(@symbols) if @symbols.any?
    query_parts.concat(@signals) if @signals.any?
    query_parts.join(" ")
  end

  def search_records(project, search_query)
    MemoryRecord.search(
      query: search_query,
      project: project,
      task_external_id: @task_external_id,
      repo_path: @repo_path,
      symbols: @symbols,
      signals: @signals,
      limit: 50 # Больше чем нужно, потом отфильтруем по токенам
    )
  end

  def build_bundle(records)
    facts = []
    few_shots = []
    links = []
    total_tokens = 0

    records.each do |record|
      next if record.ttl.present? && record.ttl < Time.current

      case record.kind
      when "fact"
        token_estimate = estimate_tokens(record.content)
        if total_tokens + token_estimate <= @limit_tokens
          facts << {
            text: record.content,
            scope: record.scope || [],
            tags: record.tags || []
          }
          total_tokens += token_estimate
        end
      when "fewshot"
        token_estimate = estimate_tokens(record.content)
        if total_tokens + token_estimate <= @limit_tokens && few_shots.length < 3
          few_shots << {
            title: record.meta&.dig("title") || "Few-shot #{record.id}",
            steps: record.content.split("\n").reject(&:empty?),
            patch_ref: record.meta&.dig("patch_sha"),
            tags: record.tags || []
          }
          total_tokens += token_estimate
        end
      when "adr_link", "link"
        links << {
          title: record.meta&.dig("title") || record.content[0..100],
          url: record.meta&.dig("url") || "",
          scope: record.scope || []
        }
      end

      break if total_tokens >= @limit_tokens
    end

    confidence = calculate_confidence(records)

    {
      facts: facts,
      few_shots: few_shots,
      links: links,
      confidence: confidence
    }
  end

  def estimate_tokens(content)
    # Грубая оценка: ~4 символа на токен
    content.length / 4
  end

  def calculate_confidence(records)
    return 0.0 unless records.any?

    [ (records.count.to_f / 10.0).clamp(0.0, 1.0), 0.5 ].max
  end

  def empty_result
    {
      facts: [],
      few_shots: [],
      links: [],
      confidence: 0.0
    }
  end
end
