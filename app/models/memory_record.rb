class MemoryRecord < ApplicationRecord
  belongs_to :project

  has_neighbors :embedding

  KINDS = %w[fact fewshot pattern adr_link gotcha rule].freeze

  validates :content, presence: true
  validates :project_id, presence: true
  validates :kind, inclusion: { in: KINDS, message: "must be one of: #{KINDS.join(', ')}" }, allow_nil: true

  scope :active, -> { where("ttl IS NULL OR ttl > ?", Time.current) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }
  scope :by_kind, ->(kind) { where(kind: kind) if kind.present? }
  scope :with_scope, ->(scopes) { where("scope && ?", Array(scopes)) if scopes.present? }
  scope :with_tags, ->(tags) { where("tags && ?", Array(tags)) if tags.present? }
  scope :search_content, ->(query) { where("content ILIKE ?", "%#{query}%") if query.present? }
  scope :for_task, ->(task_id) { where(task_external_id: task_id) if task_id.present? }

  def self.search(query:, project:, task_external_id: nil, repo_path: nil, symbols: [], signals: [], limit: 10)
    relation = active.for_project(project.id)

    # Фильтрация по task_external_id (если указан)
    relation = relation.for_task(task_external_id) if task_external_id.present?

    # Поиск по тексту контента (базовый текстовый поиск)
    # Если query пустой, но есть task_external_id, возвращаем все записи для задачи
    if query.present?
      relation = relation.search_content(query)
    end

    # Фильтрация по scope (если repo_path указан)
    if repo_path.present?
      scopes = repo_path.split("/").reject(&:empty?)
      relation = relation.with_scope(scopes) if scopes.any?
    end

    # Фильтрация по signals как тегам
    if signals.any?
      relation = relation.with_tags(signals)
    end

    relation.order(created_at: :desc).limit(limit)
  end
end
