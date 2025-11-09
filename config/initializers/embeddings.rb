module Memories
  module Embeddings
    QWEN_SOURCE = "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF"
    DEFAULT_LOCAL_MODEL = "Qwen3-Embedding-0.6B-Q8_0.gguf"

    class << self
      def provider_key
        ENV.fetch("MEMORY_EMBEDDING_PROVIDER", "local_1024").to_sym
      end

      def providers
        {
          local_1024: local_1024_config,
          openai_1536: openai_1536_config
        }.freeze
      end

      def config
        providers.fetch(provider_key)
      end

      private

      def local_1024_config
        {
          name: "qwen3-embedding-0_6b-q4",
          dimension: 1024,
          endpoint: ENV.fetch("MEMORY_EMBEDDING_ENDPOINT", "http://127.0.0.1:8081/embed"),
          model_path: ENV.fetch("MEMORY_EMBEDDING_MODEL_PATH", default_model_path),
          source: QWEN_SOURCE,
          output_dimension: ENV.fetch("MEMORY_EMBEDDING_OUTPUT_DIM", 1024).to_i
        }
      end

      def openai_1536_config
        {
          name: "text-embedding-3-small",
          dimension: 1536,
          api_key: Rails.application.credentials.openai_api_key || ENV["OPENAI_API_KEY"]
        }
      end

      def default_model_path
        Rails.root.join("tmp", "embeddings", DEFAULT_LOCAL_MODEL).to_s
      end
    end
  end
end

Rails.application.config.x.memories ||= ActiveSupport::OrderedOptions.new
Rails.application.config.x.memories.embedding_provider = Memories::Embeddings.provider_key
Rails.application.config.x.memories.embedding_providers = Memories::Embeddings.providers
