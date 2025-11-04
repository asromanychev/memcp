class CreateMemoryRecords < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'vector' unless extension_enabled?('vector')

    create_table :memory_records do |t|
      t.references :project, null: false, foreign_key: true
      t.text :content, null: false
      t.vector :embedding, limit: 1536  # OpenAI embedding dimension
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Индекс project_id создается автоматически через t.references
    add_index :memory_records, :metadata, using: :gin
    add_index :memory_records, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
  end
end
