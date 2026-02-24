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

ActiveRecord::Schema[8.0].define(version: 2026_02_23_154554) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "build_items", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "position"
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "links"
    t.index ["user_id", "completed"], name: "index_build_items_on_user_id_and_completed"
    t.index ["user_id", "position"], name: "index_build_items_on_user_id_and_position"
    t.index ["user_id"], name: "index_build_items_on_user_id"
  end

  create_table "export_jobs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "progress", default: 0, null: false
    t.string "file_path"
    t.boolean "password_protected", default: false, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "kind", default: 0, null: false
    t.index ["created_at"], name: "index_export_jobs_on_created_at"
    t.index ["user_id", "status"], name: "index_export_jobs_on_user_id_and_status"
    t.index ["user_id"], name: "index_export_jobs_on_user_id"
  end

  create_table "idea_lists", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.integer "list_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "list_id"], name: "index_idea_lists_on_idea_id_and_list_id", unique: true
    t.index ["idea_id"], name: "index_idea_lists_on_idea_id"
    t.index ["list_id", "position"], name: "index_idea_lists_on_list_id_and_position"
    t.index ["list_id"], name: "index_idea_lists_on_list_id"
  end

  create_table "idea_topologies", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.integer "topology_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "topology_id"], name: "index_idea_topologies_on_idea_id_and_topology_id", unique: true
    t.index ["idea_id"], name: "index_idea_topologies_on_idea_id"
    t.index ["topology_id"], name: "index_idea_topologies_on_topology_id"
  end

  create_table "ideas", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title"
    t.integer "state"
    t.integer "trl"
    t.integer "difficulty"
    t.integer "opportunity"
    t.integer "timing"
    t.decimal "computed_score"
    t.integer "attempt_count"
    t.datetime "cool_off_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "template_id"
    t.text "metadata"
    t.text "difficulty_explanation"
    t.text "opportunity_explanation"
    t.text "timing_explanation"
    t.boolean "email_ingested", default: false, null: false
    t.string "integrity_hash"
    t.index ["computed_score"], name: "index_ideas_on_computed_score"
    t.index ["cool_off_until"], name: "index_ideas_on_cool_off_until"
    t.index ["integrity_hash"], name: "index_ideas_on_integrity_hash"
    t.index ["state"], name: "index_ideas_on_state"
    t.index ["template_id"], name: "index_ideas_on_template_id"
    t.index ["user_id"], name: "index_ideas_on_user_id"
  end

  create_table "lists", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "position"], name: "index_lists_on_user_id_and_position", unique: true
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "templates", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.boolean "is_default", default: false, null: false
    t.text "field_definitions", null: false
    t.text "section_order", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "tab_definitions"
    t.index ["user_id", "is_default"], name: "index_templates_on_user_id_and_is_default"
    t.index ["user_id", "name"], name: "index_templates_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_templates_on_user_id"
  end

  create_table "topologies", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "parent_id"
    t.string "name", null: false
    t.integer "topology_type", default: 1, null: false
    t.string "color"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_topologies_on_parent_id"
    t.index ["user_id", "name"], name: "index_topologies_on_user_id_and_name", unique: true
    t.index ["user_id", "parent_id"], name: "index_topologies_on_user_id_and_parent_id"
    t.index ["user_id"], name: "index_topologies_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "name"
    t.text "settings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.integer "parent_version_id"
    t.text "commit_message", null: false
    t.text "snapshot_data", null: false
    t.text "diff_summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "created_at"], name: "index_versions_on_idea_id_and_created_at"
    t.index ["idea_id"], name: "index_versions_on_idea_id"
    t.index ["parent_version_id"], name: "index_versions_on_parent_version_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "build_items", "users"
  add_foreign_key "export_jobs", "users"
  add_foreign_key "idea_lists", "ideas"
  add_foreign_key "idea_lists", "lists"
  add_foreign_key "idea_topologies", "ideas"
  add_foreign_key "idea_topologies", "topologies"
  add_foreign_key "ideas", "templates"
  add_foreign_key "ideas", "users"
  add_foreign_key "lists", "users"
  add_foreign_key "templates", "users"
  add_foreign_key "topologies", "topologies", column: "parent_id"
  add_foreign_key "topologies", "users"
  add_foreign_key "versions", "ideas"
  add_foreign_key "versions", "versions", column: "parent_version_id"
end
