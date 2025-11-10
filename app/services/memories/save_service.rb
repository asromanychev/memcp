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
      ActiveRecord::Base.transaction do
        project = upsert_project
        record = create_record(project)
        @result = serialize_record(record)
        enqueue_embedding(record)
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

    def create_record(project)
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
        meta: meta
      )
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
      Memories::GenerateEmbeddingJob.perform_later(memory_record_id: record.id)
    end

    def fetch_param(key)
      params[key] || params[key.to_s]
    end
  end
end
