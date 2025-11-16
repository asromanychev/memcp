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

  desc "Generate deduplication hashes (simhash, minhash) for records missing them"
  task generate_deduplication_hashes: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", 1000).to_i
    scope = MemoryRecord.where("simhash IS NULL OR minhash IS NULL OR array_length(minhash, 1) IS NULL")
    total = scope.count

    if total.zero?
      puts "[memories:generate_deduplication_hashes] No records require deduplication hashes."
      next
    end

    puts "[memories:generate_deduplication_hashes] Found #{total} records without deduplication hashes (batch size: #{batch_size})."

    processed = 0
    errors = 0

    batch_index = 0
    scope.in_batches(of: batch_size) do |relation|
      batch_index += 1
      relation.find_each do |record|
        begin
          dedup_service = Memories::DeduplicationService.call(params: { content: record.content })

          if dedup_service.success?
            record.update!(
              simhash: dedup_service.result[:simhash],
              minhash: dedup_service.result[:minhash]
            )
            processed += 1
          else
            errors += 1
            puts "[memories:generate_deduplication_hashes] Error for record #{record.id}: #{dedup_service.errors.full_messages.join(', ')}"
          end
        rescue StandardError => e
          errors += 1
          puts "[memories:generate_deduplication_hashes] Exception for record #{record.id}: #{e.message}"
        end
      end

      remaining = [total - processed - errors, 0].max
      puts "[memories:generate_deduplication_hashes] Batch #{batch_index}: processed #{processed}, errors #{errors}, #{remaining} remaining."
    end

    puts "[memories:generate_deduplication_hashes] Completed: #{processed} processed, #{errors} errors."
  end
end

