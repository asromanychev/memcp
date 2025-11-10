namespace :memories do
  desc "Enqueue embedding generation jobs for records missing embedding_1024"
  task generate_embeddings: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", 100).to_i
    scope = MemoryRecord.where(embedding_1024: nil)
    total = scope.count

    if total.zero?
      puts "[memories:generate_embeddings] No records require embeddings."
      next
    end

    puts "[memories:generate_embeddings] Found #{total} records without embeddings (batch size: #{batch_size})."

    enqueued = 0

    batch_index = 0
    scope.in_batches(of: batch_size) do |relation|
      batch_index += 1
      ids = relation.pluck(:id)
      ids.each do |record_id|
        Memories::GenerateEmbeddingJob.perform_later(memory_record_id: record_id)
      end
      enqueued += ids.size
      remaining = [total - enqueued, 0].max
      puts "[memories:generate_embeddings] Batch #{batch_index}: enqueued #{ids.size} jobs, #{remaining} remaining."
    end

    puts "[memories:generate_embeddings] Completed enqueue for #{enqueued} records."
  end
end

