# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_11_09_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "memory_records", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.text "content", null: false
    t.vector "embedding", limit: 1536
    t.jsonb "metadata", default: {}
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "task_external_id"
    t.string "kind"
    t.string "owner"
    t.datetime "ttl"
    t.jsonb "quality", default: {}
    t.jsonb "meta", default: {}
    t.text "scope", default: [], array: true
    t.text "tags", default: [], array: true
    t.vector "embedding_1024", limit: 1024
    t.index ["embedding"], name: "index_memory_records_on_embedding", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["embedding_1024"], name: "index_memory_records_on_embedding_1024", opclass: :vector_cosine_ops, using: :ivfflat
    t.index ["kind"], name: "index_memory_records_on_kind"
    t.index ["metadata"], name: "index_memory_records_on_metadata", using: :gin
    t.index ["project_id"], name: "index_memory_records_on_project_id"
    t.index ["scope"], name: "index_memory_records_on_scope", using: :gin
    t.index ["tags"], name: "index_memory_records_on_tags", using: :gin
    t.index ["task_external_id"], name: "index_memory_records_on_task_external_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.string "path", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "key"
    t.jsonb "settings", default: {}
    t.index ["key"], name: "index_projects_on_key", unique: true
    t.index ["path"], name: "index_projects_on_path", unique: true
  end

  add_foreign_key "memory_records", "projects", name: "memory_records_project_id_fkey", on_delete: :cascade
end
