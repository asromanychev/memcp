require "set"

class MemoryRecord < ApplicationRecord
  belongs_to :project

  has_neighbors :embedding
  has_neighbors :embedding_1024

  KINDS = %w[fact fewshot pattern adr_link gotcha rule].freeze

  validates :content, presence: true
  validates :project_id, presence: true
  validates :kind, inclusion: { in: KINDS, message: "must be one of: #{KINDS.join(', ')}" }, allow_nil: true

  scope :active, -> { where("ttl IS NULL OR ttl > ?", Time.current) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }
  scope :by_kind, ->(kind) { where(kind: kind) if kind.present? }
  scope :with_scope, ->(scopes) { where("scope && ARRAY[?]::text[]", Array(scopes)) if scopes.present? }
  scope :with_tags, ->(tags) { where("tags && ARRAY[?]::text[]", Array(tags)) if tags.present? }
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

    # Фильтрация по scope: repo_path и symbols
    scopes = []
    scopes.concat(repo_path.split("/").reject(&:empty?)) if repo_path.present?
    scopes.concat(Array(symbols).compact_blank) if symbols.present?
    relation = relation.with_scope(scopes) if scopes.any?

    # Фильтрация по signals как тегам
    tag_filters = Array(signals).compact_blank
    relation = relation.with_tags(tag_filters) if tag_filters.any?

    relation.order(created_at: :desc).limit(limit)
  end

  # Поиск похожих записей по контенту
  # @param content [String] контент для поиска
  # @param project_id [Integer] ID проекта
  # @param threshold [Float] порог схожести (0.0-1.0), по умолчанию 0.85
  # @return [ActiveRecord::Relation] отсортированные по схожести записи
  def self.find_similar(content:, project_id:, threshold: 0.85)
    # Генерируем хеши для входного контента
    dedup_service = Memories::DeduplicationService.call(params: { content: content })
    return none unless dedup_service.success?

    query_simhash = dedup_service.result[:simhash]
    query_minhash = dedup_service.result[:minhash]

    return none if query_simhash.zero? || query_minhash.empty?

    # Быстрый поиск кандидатов по SimHash (Hamming distance)
    # Используем приблизительный поиск: ищем записи с похожим SimHash
    candidates = for_project(project_id)
                 .where.not(simhash: nil)
                 .where("simhash IS NOT NULL")
                 .to_a

    # Фильтруем по Hamming distance (максимальное расстояние для threshold)
    # Hamming distance = количество отличающихся битов
    # Для threshold 0.85 максимальное расстояние ≈ 64 * (1 - 0.85) = 9.6 ≈ 10
    max_hamming_distance = ((1.0 - threshold) * 64).ceil

    similar_candidates = candidates.select do |record|
      hamming_distance(query_simhash, record.simhash) <= max_hamming_distance
    end

    return none if similar_candidates.empty?

    # Точное сравнение через MinHash (Jaccard similarity)
    similar_records = similar_candidates.map do |record|
      similarity = jaccard_similarity(query_minhash, record.minhash || [])
      [record, similarity]
    end.select { |_record, similarity| similarity >= threshold }
       .sort_by { |_record, similarity| -similarity }
       .map(&:first)

    # Возвращаем как ActiveRecord::Relation через where(id: ...)
    where(id: similar_records.map(&:id))
  end

  # Вычисление Hamming distance между двумя числами
  # @param a [Integer] первое число
  # @param b [Integer] второе число
  # @return [Integer] количество отличающихся битов
  def self.hamming_distance(a, b)
    (a ^ b).to_s(2).count("1")
  end

  # Вычисление Jaccard similarity между двумя массивами MinHash
  # @param a [Array<String>] первый массив хешей
  # @param b [Array<String>] второй массив хешей
  # @return [Float] коэффициент схожести (0.0-1.0)
  def self.jaccard_similarity(a, b)
    return 0.0 if a.empty? || b.empty?

    set_a = Set.new(a)
    set_b = Set.new(b)

    intersection = (set_a & set_b).size
    union = (set_a | set_b).size

    return 0.0 if union.zero?

    intersection.to_f / union
  end
end
