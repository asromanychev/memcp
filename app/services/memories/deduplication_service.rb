module Memories
  class DeduplicationService
    include ActiveModelService

    # Количество хешей для MinHash (больше = точнее, но медленнее)
    MINHASH_SIZE = 128
    # Размер n-gram для токенизации
    NGRAM_SIZE = 3

    def initialize(params:)
      super()
      @params = params || {}
      @result = {}
      extract_attributes
    end

    private

    attr_reader :params, :content

    def validate_call
      errors.add(:base, "content is required") if content.blank?
    end

    def perform
      normalized_content = normalize_content(content)
      simhash_value = compute_simhash(normalized_content)
      minhash_values = compute_minhash(normalized_content)

      @result = {
        simhash: simhash_value,
        minhash: minhash_values
      }
    end

    def extract_attributes
      @content = params[:content].to_s
    end

    def normalize_content(text)
      # Нормализация: lowercase, удаление лишних пробелов, удаление спецсимволов
      text.downcase
          .gsub(/[^\p{L}\p{N}\s]/, " ") # Заменяем спецсимволы на пробелы
          .gsub(/\s+/, " ")              # Множественные пробелы в один
          .strip
    end

    def compute_simhash(text)
      return 0 if text.blank?

      # Разбиваем на n-grams
      ngrams = generate_ngrams(text, NGRAM_SIZE)
      return 0 if ngrams.empty?

      # Создаем вектор весов (64 бита)
      vector = Array.new(64, 0)

      ngrams.each do |ngram|
        # Хеш n-gram
        hash = ngram.hash
        # Для каждого бита в хеше
        64.times do |i|
          # Если бит установлен, увеличиваем вес, иначе уменьшаем
          vector[i] += (hash & (1 << i)).zero? ? -1 : 1
        end
      end

      # Преобразуем вектор в битовую строку
      # Ограничиваем до 63 бит для совместимости с PostgreSQL bigint (signed)
      simhash = 0
      63.times do |i|
        simhash |= (1 << i) if vector[i] > 0
      end

      simhash
    end

    def compute_minhash(text)
      return [] if text.blank?

      # Разбиваем на n-grams
      ngrams = generate_ngrams(text, NGRAM_SIZE)
      return [] if ngrams.empty?

      # Генерируем MINHASH_SIZE разных хеш-функций
      # Используем простое линейное хеширование: hash = (a * value + b) % prime
      minhashes = []

      MINHASH_SIZE.times do |i|
        # Параметры для каждой хеш-функции
        a = 31 + i * 7
        b = 17 + i * 3
        prime = 2_147_483_647 # Большое простое число

        # Находим минимальный хеш среди всех n-grams
        min_hash = ngrams.map do |ngram|
          value = ngram.hash.abs
          (a * value + b) % prime
        end.min

        minhashes << min_hash.to_s
      end

      minhashes
    end

    def generate_ngrams(text, n)
      return [] if text.length < n

      ngrams = []
      (0..text.length - n).each do |i|
        ngrams << text[i, n]
      end
      ngrams.uniq
    end
  end
end

