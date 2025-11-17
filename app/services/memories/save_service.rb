module Memories
  class SaveService
    include ActiveModelService

    def initialize(params:)
      super()
      @params = params || {}
      @result = {}
      extract_attributes
    end

    private

    attr_reader :params, :project_key, :task_external_id, :kind, :content,
                :scope, :tags, :owner, :ttl, :quality, :meta

    def validate_call
      errors.add(:base, "project_key is required") if project_key.blank?
      errors.add(:base, "kind is required") if kind.blank?
      errors.add(:base, "content is required") if content.blank?
      if kind.present? && !MemoryRecord::KINDS.include?(kind)
        errors.add(:base, "kind must be one of: #{MemoryRecord::KINDS.join(', ')}")
      end
    end

    def perform
      saved_record = nil
      ActiveRecord::Base.transaction do
        project = upsert_project

        # Генерация хешей для дедупликации
        dedup_result = Memories::DeduplicationService.call(params: { content: content })
        unless dedup_result.success?
          errors.add(:base, "Failed to generate deduplication hashes: #{dedup_result.errors.full_messages.join(', ')}")
          return
        end

        # Поиск похожих записей
        similar = MemoryRecord.find_similar(
          content: content,
          project_id: project.id,
          threshold: 0.85
        ).first

        saved_record = if similar
                         update_existing_record(similar, dedup_result.result)
                       else
                         create_new_record(project, dedup_result.result)
                       end

        @result = serialize_record(saved_record)
      end

      # Вызываем enqueue_embedding вне транзакции, чтобы ошибка queue не откатывала сохранение
      if saved_record
        enqueue_embedding(saved_record)
      end
    rescue ActiveRecord::RecordInvalid => e
      errors.merge!(e.record.errors)
    rescue StandardError => e
      errors.add(:base, e.message)
    end

    def extract_attributes
      @project_key = fetch_param(:project_key).presence
      @task_external_id = fetch_param(:task_external_id).presence
      @kind = fetch_param(:kind).presence
      @content = fetch_param(:content).to_s
      @scope = Array(fetch_param(:scope)).compact_blank
      @tags = Array(fetch_param(:tags)).compact_blank
      @owner = fetch_param(:owner).presence
      @ttl = fetch_param(:ttl)
      @quality = fetch_param(:quality).presence || {}
      @meta = fetch_param(:meta).presence || {}
    end

    def upsert_project
      project = Project.find_or_initialize_by(key: project_key)
      if project.new_record?
        project.name = project_key
        project.path = project_key
      end
      project.save!
      project
    end

    def create_new_record(project, dedup_hashes)
      MemoryRecord.create!(
        project_id: project.id,
        task_external_id: task_external_id,
        kind: kind,
        content: content,
        scope: scope,
        tags: tags,
        owner: owner,
        ttl: ttl,
        quality: quality,
        meta: meta,
        simhash: dedup_hashes[:simhash],
        minhash: dedup_hashes[:minhash]
      )
    end

    def update_existing_record(record, dedup_hashes)
      # Объединяем теги
      merged_tags = ((record.tags || []) + tags).uniq.compact_blank

      # Объединяем quality (берем лучшее значение)
      merged_quality = merge_quality(record.quality || {}, quality)

      # Обновляем контент если новый длиннее или если это явное обновление
      new_content = if content.length > record.content.length
                      content
                    else
                      record.content
                    end

      record.update!(
        content: new_content,
        tags: merged_tags,
        quality: merged_quality,
        simhash: dedup_hashes[:simhash],
        minhash: dedup_hashes[:minhash],
        updated_at: Time.current
      )

      record
    end

    def merge_quality(old_quality, new_quality)
      merged = (old_quality || {}).dup

      # Для числовых метрик берем максимум
      %w[novelty usefulness].each do |key|
        old_val = old_quality&.dig(key).to_f
        new_val = new_quality&.dig(key).to_f
        merged[key] = [old_val, new_val].max if old_val > 0 || new_val > 0
      end

      # Для risk берем максимум (больше риск = хуже)
      old_risk = old_quality&.dig("risk").to_f
      new_risk = new_quality&.dig("risk").to_f
      merged["risk"] = [old_risk, new_risk].max if old_risk > 0 || new_risk > 0

      # Объединяем остальные поля
      merged.merge(new_quality || {})
    end

    def serialize_record(record)
      {
        status: "success",
        id: record.id,
        project_id: record.project_id,
        kind: record.kind,
        content: record.content,
        scope: record.scope,
        tags: record.tags,
        ttl: record.ttl,
        quality: record.quality,
        meta: record.meta
      }
    end

    def enqueue_embedding(record)
      begin
        GenerateEmbeddingJob.perform_async(record.id)
      rescue StandardError => e
        # Если произошла ошибка, логируем, но не падаем
        Rails.logger.warn("Не удалось поставить задачу генерации embedding в очередь: #{e.class} - #{e.message}")
        nil
      end
    end
    def fetch_param(key)
      params[key] || params[key.to_s]
    end
  end
end
