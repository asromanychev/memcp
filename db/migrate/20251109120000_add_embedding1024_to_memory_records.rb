class AddEmbedding1024ToMemoryRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :memory_records, :embedding_1024, :vector, limit: 1024
    add_index :memory_records, :embedding_1024, using: :ivfflat, opclass: :vector_cosine_ops
  end
end
