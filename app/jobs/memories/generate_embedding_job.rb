module Memories
  class GenerateEmbeddingJob < ApplicationJob
    queue_as :embeddings

    retry_on StandardError, attempts: 3, wait: ->(executions) { (2**(executions - 1)).seconds }

    def perform(memory_record_id:)
      record = MemoryRecord.find_by(id: memory_record_id)
      return if record.nil?
      return if record.embedding_1024.present?

      service = Memories::EmbeddingService.call(params: { content: record.content })
      unless service.success?
        Rails.logger.warn(
          "[Memories::GenerateEmbeddingJob] failed for MemoryRecord##{record.id}: #{service.errors.full_messages.join(', ')}"
        )
        raise StandardError, "embedding generation failed"
      end

      record.update!(embedding_1024: service.result)
    end
  end
end

