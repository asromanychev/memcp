require "json"
require "net/http"

module Memories
  class EmbeddingService
    DEFAULT_OPEN_TIMEOUT = 3
    DEFAULT_READ_TIMEOUT = 10

    def self.call(params:)
      new(params).call
    end

    attr_reader :errors, :result

    def initialize(params)
      @params = params || {}
      @errors = []
      @result = []
      @provider_key = Rails.application.config.x.memories.embedding_provider
      @provider_config = Memories::Embeddings.providers[@provider_key]
    end

    def call
      extract_attributes
      validate!
      return self if errors.any?

      if provider_config.blank?
        errors << "Unknown embedding provider: #{provider_key}"
        return self
      end

      case provider_key
      when :local_1024
        perform_local_request
      when :openai_1536
        errors << "openai_1536 provider is not implemented yet"
      else
        errors << "Unknown embedding provider: #{provider_key}"
      end

      self
    end

    def success?
      errors.empty?
    end

    private

    attr_reader :params, :content, :provider_key, :provider_config

    def extract_attributes
      @content = params[:content].to_s
    end

    def validate!
      errors << "content is required" if content.blank?
    end

    def perform_local_request
      endpoint = provider_config[:endpoint]
      unless endpoint.present?
        errors << "local embedding endpoint is not configured"
        return
      end

      uri = URI.parse(endpoint)
      response = http_post(uri, inputs: [ content ])
      unless response.is_a?(Net::HTTPSuccess)
        errors << "embedding provider responded with status #{response.code}"
        return
      end

      parsed = parse_json(response.body)
      return if parsed.nil?

      embeddings = parsed["embeddings"]
      unless embeddings.is_a?(Array) && embeddings.first.is_a?(Array)
        errors << "embedding provider returned invalid payload"
        return
      end

      vector = embeddings.first
      dimension = provider_config[:dimension] || provider_config[:output_dimension]
      @result = normalise_vector(vector, dimension)
    rescue StandardError => e
      Rails.logger.error("[Memories::EmbeddingService] #{e.class}: #{e.message}")
      errors << "embedding provider request failed"
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
      errors << "embedding provider returned invalid payload"
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
