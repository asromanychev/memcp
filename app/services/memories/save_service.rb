# frozen_string_literal: true

class Memories::SaveService
  def self.call(params:)
    new(params).call
  end

  def initialize(params)
    @project_key = params[:project_key] || params["project_key"]
    @task_external_id = params[:task_external_id] || params["task_external_id"]
    @kind = params[:kind] || params["kind"]
    @content = params[:content] || params["content"]
    @scope = params[:scope] || params["scope"] || []
    @tags = params[:tags] || params["tags"] || []
    @owner = params[:owner] || params["owner"]
    @ttl = parse_ttl(params[:ttl] || params["ttl"])
    @quality = params[:quality] || params["quality"] || {}
    @meta = params[:meta] || params["meta"] || {}
    @errors = []
  end

  def call
    return self unless valid?

    @result = save_record
    self
  rescue ActiveRecord::RecordInvalid => e
    @errors.concat(e.record.errors.full_messages)
    self
  end

  def success?
    @errors.empty?
  end

  def errors
    @errors
  end

  def result
    @result
  end

  private

  def valid?
    if @project_key.blank?
      @errors << "project_key is required"
      return false
    end

    if @kind.blank?
      @errors << "kind is required"
      return false
    end

    if @content.blank?
      @errors << "content is required"
      return false
    end

    unless MemoryRecord::KINDS.include?(@kind)
      @errors << "kind must be one of: #{MemoryRecord::KINDS.join(', ')}"
      return false
    end

    true
  end

  def save_record
    project = find_or_create_project
    record = create_memory_record(project)

    {
      id: record.id,
      project_id: project.id,
      kind: record.kind,
      content: record.content,
      scope: record.scope,
      tags: record.tags,
      ttl: record.ttl,
      quality: record.quality,
      meta: record.meta
    }
  end

  def find_or_create_project
    project = Project.find_or_initialize_by(key: @project_key)
    if project.new_record?
      project.name = @project_key
      project.path = @project_key # Используем key как path для новых проектов
    end
    project.save!
    project
  end

  def create_memory_record(project)
    record = MemoryRecord.new(
      project_id: project.id,
      task_external_id: @task_external_id,
      kind: @kind,
      content: @content,
      scope: @scope,
      tags: @tags,
      owner: @owner,
      ttl: @ttl,
      quality: @quality,
      meta: @meta
    )

    # NOTE: embeddings будут добавлены на следующей итерации (воркер/сервис)
    record.save!
    record
  end

  def parse_ttl(ttl_value)
    return nil if ttl_value.blank?

    case ttl_value
    when String
      Time.parse(ttl_value)
    when Time, DateTime, ActiveSupport::TimeWithZone
      ttl_value
    else
      nil
    end
  rescue ArgumentError, TypeError
    nil
  end
end
