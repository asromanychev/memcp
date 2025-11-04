class MemoryController < ApplicationController
  # POST /recall
  # Реализация: текстовый поиск + формирование bundle
  def recall
    payload = params.to_unsafe_h

    project_key       = payload["project_key"]
    task_external_id  = payload["task_external_id"]
    repo_path         = payload["repo_path"]
    symbols           = payload["symbols"] || []
    signals           = payload["signals"] || []
    limit_tokens      = (payload["limit_tokens"] || 2000).to_i

    unless project_key.present?
      return render json: { status: "error", message: "project_key is required" }, status: :unprocessable_entity
    end

    project = Project.find_by(key: project_key)
    unless project
      return render json: {
        facts: [],
        few_shots: [],
        links: [],
        confidence: 0.0
      }, status: :ok
    end

    # Формируем поисковый запрос из доступных данных (только для текстового поиска)
    query_parts = []
    query_parts.concat(symbols) if symbols.any?
    query_parts.concat(signals) if signals.any?
    search_query = query_parts.join(" ")

    # Поиск воспоминаний
    # task_external_id передается отдельно для фильтрации
    records = MemoryRecord.search(
      query: search_query,
      project: project,
      task_external_id: task_external_id,
      repo_path: repo_path,
      symbols: symbols,
      signals: signals,
      limit: 50 # Больше чем нужно, потом отфильтруем по токенам
    )

    # Формируем bundle
    facts = []
    few_shots = []
    links = []
    total_tokens = 0

    records.each do |record|
      next if record.ttl.present? && record.ttl < Time.current

      case record.kind
      when "fact"
        token_estimate = record.content.length / 4 # грубая оценка
        if total_tokens + token_estimate <= limit_tokens
          facts << {
            text: record.content,
            scope: record.scope || [],
            tags: record.tags || []
          }
          total_tokens += token_estimate
        end
      when "fewshot"
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
      when "adr_link", "link"
        links << {
          title: record.meta&.dig("title") || record.content[0..100],
          url: record.meta&.dig("url") || "",
          scope: record.scope || []
        }
      end

      break if total_tokens >= limit_tokens
    end

    # Рассчитываем confidence на основе количества найденных результатов
    confidence = [ (records.count.to_f / 10.0).clamp(0.0, 1.0), 0.5 ].max if records.any?

    render json: {
      facts: facts,
      few_shots: few_shots,
      links: links,
      confidence: confidence || 0.0
    }, status: :ok
  end

  # POST /save
  # Реализация: upsert проекта по key и сохранение memory_record
  def save
    payload = params.to_unsafe_h

    project_key       = payload["project_key"]
    task_external_id  = payload["task_external_id"]
    kind              = payload["kind"]
    content           = payload["content"]
    scope             = payload["scope"] || []
    tags              = payload["tags"] || []
    owner             = payload["owner"]
    ttl               = payload["ttl"]
    quality           = payload["quality"] || {}
    meta              = payload["meta"] || {}

    unless project_key.present? && kind.present? && content.present?
      return render json: { status: "error", message: "project_key, kind, content are required" }, status: :unprocessable_entity
    end

    project = Project.find_or_initialize_by(key: project_key)
    if project.new_record?
      project.name = project_key
      project.path = project_key # Используем key как path для новых проектов
    end
    project.save!

    record = MemoryRecord.new(
      project_id: project.id,
      task_external_id: task_external_id,
      kind: kind,
      content: content,
      scope: scope,
      tags: tags,
      owner: owner,
      ttl: ttl,
      quality: quality,
      meta: meta
    )

    # NOTE: embeddings будут добавлены на следующей итерации (воркер/сервис)
    record.save!

    render json: {
      status: "success",
      id: record.id,
      project_id: project.id,
      kind: record.kind,
      content: record.content,
      scope: record.scope,
      tags: record.tags,
      ttl: record.ttl,
      quality: record.quality,
      meta: record.meta
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { status: "error", message: e.record.errors.full_messages }, status: :unprocessable_entity
  end
end
