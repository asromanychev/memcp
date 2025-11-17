class GenerateEmbeddingJob
  include Sidekiq::Worker

  sidekiq_options queue: :embeddings, retry: 3

  def perform(memory_record_id)
    memory_record = MemoryRecord.find(memory_record_id)

    # Generate embeddings using the embedding service
    service = Memories::EmbeddingService.call(params: { content: memory_record.content })

    if service.success?
      memory_record.update!(
        embedding: service.result,
        embedding_1024: service.result, # Сохраняем и в embedding_1024 для векторного поиска
        embedding_generated_at: Time.current
      )

      Rails.logger.info("Generated embedding for memory record #{memory_record_id}")
    else
      Rails.logger.error("Failed to generate embedding for memory record #{memory_record_id}: #{service.errors.full_messages.join(', ')}")
      raise "Embedding generation failed: #{service.errors.full_messages.join(', ')}"
    end
  end
end
