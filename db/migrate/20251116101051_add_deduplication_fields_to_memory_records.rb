class AddDeduplicationFieldsToMemoryRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :memory_records, :simhash, :bigint
    add_column :memory_records, :minhash, :text, array: true, default: []

    add_index :memory_records, :simhash
    add_index :memory_records, :minhash, using: :gin
  end
end
