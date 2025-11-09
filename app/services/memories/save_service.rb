module Memories
  class SaveService
    def self.call(params:)
      new(params).call
    end

    attr_reader :errors, :result

    def initialize(params)
      @params = params || {}
      @errors = []
      @result = {}
    end

    def call
      extract_attributes
      validate!
      return self if errors.any?

      record = nil
      ActiveRecord::Base.transaction do
        project = upsert_project
        record = create_record(project)
        @result = serialize_record(record)
      end

      Memories::GenerateEmbeddingJob.perform_later(memory_record_id: record.id) if record.present?

      self
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      self
    rescue StandardError => e
      errors << e.message
      self
    end

    def success?
      errors.empty?
    end

    private

    attr_reader :params, :project_key, :task_external_id, :kind, :content,
                :scope, :tags, :owner, :ttl, :quality, :meta

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

    def validate!
      errors << "project_key is required" if project_key.blank?
      errors << "kind is required" if kind.blank?
      errors << "content is required" if content.blank?
      if kind.present? && !MemoryRecord::KINDS.include?(kind)
        errors << "kind must be one of: #{MemoryRecord::KINDS.join(', ')}"
      end
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

    def fetch_param(key)
      params[key] || params[key.to_s]
    end
  end
end
