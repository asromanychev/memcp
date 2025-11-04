class AddSpecFieldsToProjectsAndMemoryRecords < ActiveRecord::Migration[8.0]
  def change
    change_table :projects, bulk: true do |t|
      t.string :key
      t.jsonb :settings, default: {}
    end
    add_index :projects, :key, unique: true

    change_table :memory_records, bulk: true do |t|
      t.string :task_external_id
      t.string :kind
      t.string :owner
      t.datetime :ttl
      t.jsonb :quality, default: {}
      t.jsonb :meta, default: {}
      t.text :scope, array: true, default: []
      t.text :tags, array: true, default: []
    end
    add_index :memory_records, :task_external_id
    add_index :memory_records, :kind
    add_index :memory_records, :tags, using: :gin
    add_index :memory_records, :scope, using: :gin
  end
end
