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

ActiveRecord::Schema[8.1].define(version: 2026_05_25_090000) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "ocr_error"
    t.text "ocr_metadata"
    t.string "ocr_status", default: "pending", null: false
    t.text "ocr_text"
    t.integer "position"
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["ocr_status"], name: "index_active_storage_attachments_on_ocr_status"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
    t.index ["record_type", "record_id", "name", "position"], name: "index_active_storage_attachments_on_record_position"
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_events", force: :cascade do |t|
    t.integer "agent_run_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.text "payload"
    t.text "summary"
    t.integer "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["agent_run_id"], name: "index_agent_events_on_agent_run_id"
    t.index ["target_type", "target_id"], name: "index_agent_events_on_target_type_and_target_id"
    t.index ["user_id", "event_type"], name: "index_agent_events_on_user_id_and_event_type"
    t.index ["user_id"], name: "index_agent_events_on_user_id"
  end

  create_table "agent_recommendations", force: :cascade do |t|
    t.string "action", null: false
    t.integer "agent_event_id"
    t.datetime "created_at", null: false
    t.text "payload"
    t.text "reasoning"
    t.datetime "reviewed_at"
    t.string "risk_level", default: "medium", null: false
    t.integer "status", default: 0, null: false
    t.integer "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["action"], name: "index_agent_recommendations_on_action"
    t.index ["agent_event_id"], name: "index_agent_recommendations_on_agent_event_id"
    t.index ["target_type", "target_id"], name: "index_agent_recommendations_on_target_type_and_target_id"
    t.index ["user_id", "status"], name: "index_agent_recommendations_on_user_id_and_status"
    t.index ["user_id"], name: "index_agent_recommendations_on_user_id"
  end

  create_table "agent_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_heartbeat_at"
    t.text "metadata"
    t.integer "pid"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "stopped_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "last_heartbeat_at"], name: "index_agent_runs_on_user_id_and_last_heartbeat_at"
    t.index ["user_id", "status"], name: "index_agent_runs_on_user_id_and_status"
    t.index ["user_id"], name: "index_agent_runs_on_user_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "build_items", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "links"
    t.integer "position"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "completed"], name: "index_build_items_on_user_id_and_completed"
    t.index ["user_id", "position"], name: "index_build_items_on_user_id_and_position"
    t.index ["user_id"], name: "index_build_items_on_user_id"
  end

  create_table "drawings", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "idea_id", null: false
    t.integer "position"
    t.integer "role", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "role", "position"], name: "index_drawings_on_idea_id_and_role_and_position"
    t.index ["idea_id", "updated_at"], name: "index_drawings_on_idea_id_and_updated_at"
    t.index ["idea_id"], name: "index_drawings_on_idea_id"
  end

  create_table "export_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "file_path"
    t.integer "kind", default: 0, null: false
    t.boolean "password_protected", default: false, null: false
    t.integer "progress", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["created_at"], name: "index_export_jobs_on_created_at"
    t.index ["user_id", "status"], name: "index_export_jobs_on_user_id_and_status"
    t.index ["user_id"], name: "index_export_jobs_on_user_id"
  end

  create_table "facts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
  end

  create_table "github_repositories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_branch"
    t.boolean "has_releases", default: false, null: false
    t.integer "idea_id", null: false
    t.datetime "last_checked_at"
    t.text "last_error"
    t.string "latest_release_tag"
    t.string "latest_release_url"
    t.string "name", null: false
    t.string "owner", null: false
    t.boolean "private", default: false, null: false
    t.string "repository_url", null: false
    t.datetime "updated_at", null: false
    t.index ["has_releases"], name: "index_github_repositories_on_has_releases"
    t.index ["idea_id"], name: "index_github_repositories_on_idea_id", unique: true
    t.index ["owner", "name"], name: "index_github_repositories_on_owner_and_name"
  end

  create_table "idea_agent_tokens", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "idea_id", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "active"], name: "index_idea_agent_tokens_on_idea_id_and_active"
    t.index ["idea_id"], name: "index_idea_agent_tokens_on_idea_id"
    t.index ["token_digest"], name: "index_idea_agent_tokens_on_token_digest", unique: true
  end

  create_table "idea_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "idea_id", null: false
    t.integer "kind", null: false
    t.string "name", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["idea_id", "kind", "position"], name: "index_idea_entries_on_idea_id_and_kind_and_position"
    t.index ["idea_id", "kind"], name: "index_idea_entries_on_idea_id_and_kind"
    t.index ["idea_id"], name: "index_idea_entries_on_idea_id"
  end

  create_table "idea_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "idea_id", null: false
    t.integer "list_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["idea_id", "list_id"], name: "index_idea_lists_on_idea_id_and_list_id", unique: true
    t.index ["list_id", "position"], name: "index_idea_lists_on_list_id_and_position"
    t.index ["list_id"], name: "index_idea_lists_on_list_id"
  end

  create_table "idea_topologies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "idea_id", null: false
    t.integer "topology_id", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "topology_id"], name: "index_idea_topologies_on_idea_id_and_topology_id", unique: true
    t.index ["idea_id"], name: "index_idea_topologies_on_idea_id"
    t.index ["topology_id"], name: "index_idea_topologies_on_topology_id"
  end

  create_table "ideas", force: :cascade do |t|
    t.integer "attempt_count"
    t.decimal "computed_score"
    t.datetime "cool_off_until"
    t.datetime "created_at", null: false
    t.integer "difficulty"
    t.text "difficulty_explanation"
    t.datetime "discarded_at"
    t.boolean "draft", default: false, null: false
    t.boolean "email_ingested", default: false, null: false
    t.string "integrity_hash"
    t.text "metadata"
    t.json "napkin_calculations"
    t.integer "opportunity"
    t.text "opportunity_explanation"
    t.integer "state"
    t.integer "template_id"
    t.integer "timing"
    t.text "timing_explanation"
    t.string "title"
    t.integer "trl"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["computed_score"], name: "index_ideas_on_computed_score"
    t.index ["cool_off_until"], name: "index_ideas_on_cool_off_until"
    t.index ["discarded_at"], name: "index_ideas_on_discarded_at"
    t.index ["integrity_hash"], name: "index_ideas_on_integrity_hash"
    t.index ["state"], name: "index_ideas_on_state"
    t.index ["template_id"], name: "index_ideas_on_template_id"
    t.index ["user_id", "draft"], name: "index_ideas_on_user_id_and_draft"
    t.index ["user_id"], name: "index_ideas_on_user_id"
  end

  create_table "kanban_boards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "position"], name: "index_kanban_boards_on_user_id_and_position", unique: true
    t.index ["user_id"], name: "index_kanban_boards_on_user_id"
  end

  create_table "lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kanban_board_id"
    t.string "kind", default: "kanban", null: false
    t.string "name"
    t.integer "position"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["kanban_board_id", "position"], name: "index_lists_on_kanban_board_id_and_position", unique: true, where: "kind = 'kanban'"
    t.index ["kanban_board_id"], name: "index_lists_on_kanban_board_id"
    t.index ["user_id", "kind", "position"], name: "index_lists_on_user_kind_position_named", unique: true, where: "kind = 'named'"
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "maxims", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "depth", default: 0, null: false
    t.integer "idea_id", null: false
    t.integer "parent_note_id"
    t.datetime "updated_at", null: false
    t.index ["idea_id", "created_at"], name: "index_notes_on_idea_id_and_created_at"
    t.index ["idea_id"], name: "index_notes_on_idea_id"
    t.index ["parent_note_id", "created_at"], name: "index_notes_on_parent_note_id_and_created_at"
    t.index ["parent_note_id"], name: "index_notes_on_parent_note_id"
  end

  create_table "submissions", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "idea_id"
    t.string "intake_reference", null: false
    t.integer "priority", default: 1, null: false
    t.text "raw_data"
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.string "source"
    t.string "source_reference"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["idea_id"], name: "index_submissions_on_idea_id"
    t.index ["intake_reference"], name: "index_submissions_on_intake_reference", unique: true
    t.index ["reviewed_at"], name: "index_submissions_on_reviewed_at"
    t.index ["source", "source_reference"], name: "index_submissions_on_source_and_source_reference", unique: true
    t.index ["user_id", "status"], name: "index_submissions_on_user_id_and_status"
    t.index ["user_id"], name: "index_submissions_on_user_id"
  end

  create_table "templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "field_definitions", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.text "section_order", null: false
    t.text "tab_definitions"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "is_default"], name: "index_templates_on_user_id_and_is_default"
    t.index ["user_id", "name"], name: "index_templates_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_templates_on_user_id"
  end

  create_table "todo_items", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "idea_id", null: false
    t.integer "position"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "completed"], name: "index_todo_items_on_idea_id_and_completed"
    t.index ["idea_id", "position"], name: "index_todo_items_on_idea_id_and_position"
    t.index ["idea_id"], name: "index_todo_items_on_idea_id"
  end

  create_table "topologies", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "default_field_definitions", default: "[]", null: false
    t.string "name", null: false
    t.integer "parent_id"
    t.integer "position"
    t.integer "topology_type", default: 1, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["parent_id"], name: "index_topologies_on_parent_id"
    t.index ["user_id", "parent_id", "name"], name: "index_topologies_on_user_id_and_parent_id_and_name", unique: true
    t.index ["user_id", "parent_id"], name: "index_topologies_on_user_id_and_parent_id"
    t.index ["user_id"], name: "index_topologies_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.text "settings"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.text "commit_message", null: false
    t.datetime "created_at", null: false
    t.text "diff_summary"
    t.integer "idea_id", null: false
    t.integer "parent_version_id"
    t.text "snapshot_data", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "created_at"], name: "index_versions_on_idea_id_and_created_at"
    t.index ["idea_id"], name: "index_versions_on_idea_id"
    t.index ["parent_version_id"], name: "index_versions_on_parent_version_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_events", "agent_runs"
  add_foreign_key "agent_events", "users"
  add_foreign_key "agent_recommendations", "agent_events"
  add_foreign_key "agent_recommendations", "users"
  add_foreign_key "agent_runs", "users"
  add_foreign_key "api_keys", "users"
  add_foreign_key "build_items", "users"
  add_foreign_key "drawings", "ideas"
  add_foreign_key "export_jobs", "users"
  add_foreign_key "github_repositories", "ideas"
  add_foreign_key "idea_agent_tokens", "ideas"
  add_foreign_key "idea_entries", "ideas"
  add_foreign_key "idea_lists", "ideas"
  add_foreign_key "idea_lists", "lists"
  add_foreign_key "idea_topologies", "ideas"
  add_foreign_key "idea_topologies", "topologies"
  add_foreign_key "ideas", "templates"
  add_foreign_key "ideas", "users"
  add_foreign_key "kanban_boards", "users"
  add_foreign_key "lists", "kanban_boards"
  add_foreign_key "lists", "users"
  add_foreign_key "notes", "ideas"
  add_foreign_key "notes", "notes", column: "parent_note_id"
  add_foreign_key "submissions", "ideas"
  add_foreign_key "submissions", "users"
  add_foreign_key "templates", "users"
  add_foreign_key "todo_items", "ideas"
  add_foreign_key "topologies", "topologies", column: "parent_id"
  add_foreign_key "topologies", "users"
  add_foreign_key "versions", "ideas"
  add_foreign_key "versions", "versions", column: "parent_version_id"
end
