require "json"
require "net/http"

module Memories
  class EmbeddingService
    include ActiveModelService

    DEFAULT_OPEN_TIMEOUT = 3
    DEFAULT_READ_TIMEOUT = 10

    def initialize(params:)
      super()
      @params = params || {}
      @result = []
      @provider_key = Rails.application.config.x.memories.embedding_provider
      @provider_config = Memories::Embeddings.providers[@provider_key]
      extract_attributes
    end

    private

    attr_reader :params, :content, :provider_key, :provider_config

    def validate_call
      errors.add(:base, "content is required") if content.blank?
      errors.add(:base, "Unknown embedding provider: #{provider_key}") if provider_config.blank?
      end

    def perform
      case provider_key
      when :local_1024
        perform_local_request
      when :openai_1536
        errors.add(:base, "openai_1536 provider is not implemented yet")
      else
        errors.add(:base, "Unknown embedding provider: #{provider_key}")
      end
    end

    def extract_attributes
      @content = params[:content].to_s
    end

    def perform_local_request
      endpoint = provider_config[:endpoint]
      unless endpoint.present?
        errors.add(:base, "local embedding endpoint is not configured")
        return
      end

      uri = URI.parse(endpoint)
      response = http_post(uri, inputs: [ content ])
      unless response.is_a?(Net::HTTPSuccess)
        errors.add(:base, "embedding provider responded with status #{response.code}")
        return
      end

      parsed = parse_json(response.body)
      return if parsed.nil?

      embeddings = parsed["embeddings"]
      unless embeddings.is_a?(Array) && embeddings.first.is_a?(Array)
        errors.add(:base, "embedding provider returned invalid payload")
        return
      end

      vector = embeddings.first
      dimension = provider_config[:dimension] || provider_config[:output_dimension]
      @result = normalise_vector(vector, dimension)
    rescue StandardError => e
      Rails.logger.error("[Memories::EmbeddingService] #{e.class}: #{e.message}")
      errors.add(:base, "embedding provider request failed")
    end

    def http_post(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = DEFAULT_OPEN_TIMEOUT
      http.read_timeout = DEFAULT_READ_TIMEOUT
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      http.request(request)
    end

    def parse_json(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      errors.add(:base, "embedding provider returned invalid payload")
      nil
    end

    def normalise_vector(vector, target_dimension)
      numbers = vector.map { |value| value.to_f }

      if target_dimension.to_i.positive?
        if numbers.length > target_dimension
          numbers = numbers.first(target_dimension)
        elsif numbers.length < target_dimension
          numbers += Array.new(target_dimension - numbers.length, 0.0)
        end
      end

      numbers
    end
  end
end
