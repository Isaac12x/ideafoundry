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

ActiveRecord::Schema[8.1].define(version: 2026_10_20_131500) do
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
    t.integer "position"
    t.string "ocr_status", default: "pending", null: false
    t.text "ocr_text"
    t.text "ocr_metadata"
    t.text "ocr_error"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["ocr_status"], name: "index_active_storage_attachments_on_ocr_status"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
    t.index ["record_type", "record_id", "name", "position"], name: "index_active_storage_attachments_on_record_position"
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

  create_table "activity_logs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "actor", default: "user", null: false
    t.string "action", null: false
    t.string "trackable_type"
    t.integer "trackable_id"
    t.string "trackable_name"
    t.text "details"
    t.datetime "created_at", null: false
    t.index ["trackable_type", "trackable_id"], name: "index_activity_logs_on_trackable_type_and_trackable_id"
    t.index ["user_id", "created_at"], name: "index_activity_logs_on_user_id_and_created_at"
  end

  create_table "agent_events", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "agent_run_id"
    t.string "event_type", null: false
    t.string "target_type"
    t.integer "target_id"
    t.text "summary"
    t.text "payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_run_id"], name: "index_agent_events_on_agent_run_id"
    t.index ["target_type", "target_id"], name: "index_agent_events_on_target_type_and_target_id"
    t.index ["user_id", "event_type"], name: "index_agent_events_on_user_id_and_event_type"
    t.index ["user_id"], name: "index_agent_events_on_user_id"
  end

  create_table "agent_recommendations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "agent_event_id"
    t.string "target_type"
    t.integer "target_id"
    t.string "action", null: false
    t.string "risk_level", default: "medium", null: false
    t.text "reasoning"
    t.text "payload"
    t.integer "status", default: 0, null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_agent_recommendations_on_action"
    t.index ["agent_event_id"], name: "index_agent_recommendations_on_agent_event_id"
    t.index ["target_type", "target_id"], name: "index_agent_recommendations_on_target_type_and_target_id"
    t.index ["user_id", "status"], name: "index_agent_recommendations_on_user_id_and_status"
    t.index ["user_id"], name: "index_agent_recommendations_on_user_id"
  end

  create_table "agent_runs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "pid"
    t.datetime "started_at"
    t.datetime "stopped_at"
    t.datetime "last_heartbeat_at"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "last_heartbeat_at"], name: "index_agent_runs_on_user_id_and_last_heartbeat_at"
    t.index ["user_id", "status"], name: "index_agent_runs_on_user_id_and_status"
    t.index ["user_id"], name: "index_agent_runs_on_user_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "token_digest", null: false
    t.string "name", null: false
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "token"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_keys_on_user_id"
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
    t.boolean "pinned", default: false, null: false
    t.index ["user_id", "completed"], name: "index_build_items_on_user_id_and_completed"
    t.index ["user_id", "pinned", "position"], name: "index_build_items_on_user_id_and_pinned_and_position"
    t.index ["user_id", "position"], name: "index_build_items_on_user_id_and_position"
    t.index ["user_id"], name: "index_build_items_on_user_id"
  end

  create_table "capture_jobs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "public_id", null: false
    t.string "url", null: false
    t.string "file_format", default: "md", null: false
    t.string "state", default: "queued", null: false
    t.datetime "claimed_at"
    t.datetime "finished_at"
    t.string "filename"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "source_index"
    t.string "dir"
    t.index ["public_id"], name: "index_capture_jobs_on_public_id", unique: true
    t.index ["user_id", "state", "created_at"], name: "index_capture_jobs_on_user_id_and_state_and_created_at"
    t.index ["user_id"], name: "index_capture_jobs_on_user_id"
  end

  create_table "drawings", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.string "title", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.integer "position"
    t.index ["idea_id", "role", "position"], name: "index_drawings_on_idea_id_and_role_and_position"
    t.index ["idea_id", "updated_at"], name: "index_drawings_on_idea_id_and_updated_at"
    t.index ["idea_id"], name: "index_drawings_on_idea_id"
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

  create_table "facts", force: :cascade do |t|
    t.text "body"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "github_repositories", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.string "repository_url", null: false
    t.string "owner", null: false
    t.string "name", null: false
    t.string "default_branch"
    t.boolean "private", default: false, null: false
    t.boolean "has_releases", default: false, null: false
    t.string "latest_release_tag"
    t.string "latest_release_url"
    t.datetime "last_checked_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["has_releases"], name: "index_github_repositories_on_has_releases"
    t.index ["idea_id"], name: "index_github_repositories_on_idea_id", unique: true
    t.index ["owner", "name"], name: "index_github_repositories_on_owner_and_name"
  end

  create_table "idea_agent_tokens", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.string "token_digest", null: false
    t.string "name", null: false
    t.datetime "last_used_at"
    t.datetime "expires_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "active"], name: "index_idea_agent_tokens_on_idea_id_and_active"
    t.index ["idea_id"], name: "index_idea_agent_tokens_on_idea_id"
    t.index ["token_digest"], name: "index_idea_agent_tokens_on_token_digest", unique: true
  end

  create_table "idea_entries", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.integer "kind", null: false
    t.string "name", null: false
    t.string "url"
    t.text "description"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "kind", "position"], name: "index_idea_entries_on_idea_id_and_kind_and_position"
    t.index ["idea_id", "kind"], name: "index_idea_entries_on_idea_id_and_kind"
    t.index ["idea_id"], name: "index_idea_entries_on_idea_id"
  end

  create_table "idea_kb_links", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.string "source_path", null: false
    t.string "relative_path", default: "", null: false
    t.string "entry_type", default: "file", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "source_path", "relative_path"], name: "index_idea_kb_links_uniqueness", unique: true
    t.index ["idea_id"], name: "index_idea_kb_links_on_idea_id"
    t.index ["source_path", "relative_path"], name: "index_idea_kb_links_on_source_path_and_relative_path"
  end

  create_table "idea_lists", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.integer "list_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "list_id"], name: "index_idea_lists_on_idea_id_and_list_id", unique: true
    t.index ["list_id", "position"], name: "index_idea_lists_on_list_id_and_position"
    t.index ["list_id"], name: "index_idea_lists_on_list_id"
  end

  create_table "idea_themes", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.integer "theme_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "theme_id"], name: "index_idea_themes_on_idea_id_and_theme_id", unique: true
    t.index ["idea_id"], name: "index_idea_themes_on_idea_id"
    t.index ["theme_id"], name: "index_idea_themes_on_theme_id"
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
    t.datetime "discarded_at"
    t.boolean "draft", default: false, null: false
    t.json "napkin_calculations"
    t.string "tldr"
    t.string "category"
    t.integer "version_group_id"
    t.integer "version_number"
    t.boolean "version_primary", default: false, null: false
    t.boolean "for_licensing", default: false, null: false
    t.index ["computed_score"], name: "index_ideas_on_computed_score"
    t.index ["cool_off_until"], name: "index_ideas_on_cool_off_until"
    t.index ["discarded_at"], name: "index_ideas_on_discarded_at"
    t.index ["integrity_hash"], name: "index_ideas_on_integrity_hash"
    t.index ["state"], name: "index_ideas_on_state"
    t.index ["template_id"], name: "index_ideas_on_template_id"
    t.index ["user_id", "draft"], name: "index_ideas_on_user_id_and_draft"
    t.index ["user_id", "for_licensing"], name: "index_ideas_on_user_id_and_for_licensing"
    t.index ["user_id"], name: "index_ideas_on_user_id"
    t.index ["version_group_id"], name: "index_ideas_on_version_group_id"
  end

  create_table "kanban_boards", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "position"], name: "index_kanban_boards_on_user_id_and_position", unique: true
    t.index ["user_id"], name: "index_kanban_boards_on_user_id"
  end

  create_table "kb_annotations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "source_path", null: false
    t.string "relative_path", null: false
    t.string "style", default: "highlight", null: false
    t.string "color", default: "yellow", null: false
    t.integer "page"
    t.integer "start_offset", null: false
    t.integer "end_offset", null: false
    t.text "quote", null: false
    t.string "prefix", default: "", null: false
    t.string "suffix", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "source_path", "relative_path"], name: "index_kb_annotations_on_user_and_path"
    t.index ["user_id"], name: "index_kb_annotations_on_user_id"
  end

  create_table "kb_bookmarks", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "source_path", null: false
    t.string "relative_path", null: false
    t.string "label", null: false
    t.integer "page"
    t.string "cfi"
    t.float "progress"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "source_path", "relative_path"], name: "index_kb_bookmarks_on_user_and_path"
    t.index ["user_id"], name: "index_kb_bookmarks_on_user_id"
  end

  create_table "kb_downloads", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "source_index", null: false
    t.string "dir", default: "", null: false
    t.string "url", null: false
    t.string "format", default: "auto", null: false
    t.string "status", default: "pending", null: false
    t.string "filename"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "source_path"
    t.string "title"
    t.text "reference_list"
    t.string "references_state"
    t.string "archive_url"
    t.integer "attempts", default: 0, null: false
    t.string "video_id"
    t.text "transcript"
    t.string "transcript_status"
    t.integer "transcript_attempts", default: 0, null: false
    t.string "transcript_error"
    t.datetime "opened_at"
    t.integer "clip_start"
    t.integer "clip_end"
    t.text "note"
    t.index ["transcript_status"], name: "index_kb_downloads_on_transcript_status"
    t.index ["user_id", "status"], name: "index_kb_downloads_on_user_id_and_status"
    t.index ["user_id"], name: "index_kb_downloads_on_user_id"
  end

  create_table "kb_entry_preferences", force: :cascade do |t|
    t.integer "user_id", null: false
    t.text "source_path", default: "", null: false
    t.text "relative_path", default: "", null: false
    t.string "entry_type", null: false
    t.boolean "favorite", default: false, null: false
    t.string "icon_kind", default: "default", null: false
    t.string "emoji"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sort_mode"
    t.text "manual_order"
    t.index ["user_id", "source_path", "relative_path", "entry_type"], name: "index_kb_entry_preferences_on_entry", unique: true
    t.index ["user_id"], name: "index_kb_entry_preferences_on_user_id"
  end

  create_table "kb_fs_jobs", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "source_index", null: false
    t.text "source_path", null: false
    t.text "context_path", null: false
    t.string "context_kind", null: false
    t.text "target_dir", default: "", null: false
    t.text "prompt"
    t.text "transcript"
    t.string "status", default: "pending", null: false
    t.text "result_path"
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "status"], name: "index_kb_fs_jobs_on_user_id_and_status"
    t.index ["user_id"], name: "index_kb_fs_jobs_on_user_id"
  end

  create_table "kb_links", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "kind", null: false
    t.text "source_path", null: false
    t.text "relative_path", null: false
    t.text "peer_source_path", null: false
    t.text "peer_relative_path", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "kind", "source_path", "relative_path", "peer_source_path", "peer_relative_path"], name: "index_kb_links_on_pair", unique: true
    t.index ["user_id"], name: "index_kb_links_on_user_id"
  end

  create_table "kb_media_edits", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "source_index", null: false
    t.string "source_path", null: false
    t.string "relative_path", null: false
    t.string "media_kind", null: false
    t.string "status", default: "pending", null: false
    t.text "operations"
    t.string "original_sha256"
    t.string "result_sha256"
    t.string "revision_path"
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "result_relative_path"
    t.index ["source_path", "relative_path"], name: "index_kb_media_edits_on_source_path_and_relative_path"
    t.index ["user_id", "source_path", "relative_path"], name: "index_active_kb_media_edits_on_path", unique: true, where: "status IN ('pending', 'running')"
    t.index ["user_id", "status"], name: "index_kb_media_edits_on_user_id_and_status"
    t.index ["user_id"], name: "index_kb_media_edits_on_user_id"
  end

  create_table "knowledge_extractions", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "backend"
    t.string "source_kind", null: false
    t.integer "idea_id"
    t.bigint "attachment_id"
    t.bigint "output_attachment_id"
    t.integer "kb_folder_index"
    t.string "kb_path"
    t.string "output_path"
    t.string "source_filename"
    t.integer "page_count"
    t.integer "pages_done", default: 0, null: false
    t.text "markdown"
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attachment_id"], name: "index_knowledge_extractions_on_attachment_id"
    t.index ["idea_id"], name: "index_knowledge_extractions_on_idea_id"
    t.index ["status"], name: "index_knowledge_extractions_on_status"
  end

  create_table "licensor_contacts", force: :cascade do |t|
    t.integer "licensor_id", null: false
    t.datetime "occurred_at", null: false
    t.integer "channel", default: 0, null: false
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["licensor_id", "occurred_at"], name: "index_licensor_contacts_on_licensor_id_and_occurred_at"
    t.index ["licensor_id"], name: "index_licensor_contacts_on_licensor_id"
  end

  create_table "licensor_imports", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.string "filename", null: false
    t.string "status", default: "pending", null: false
    t.text "column_mapping"
    t.boolean "headers_in_first_row", default: true, null: false
    t.integer "imported_count", default: 0, null: false
    t.integer "row_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id"], name: "index_licensor_imports_on_idea_id"
  end

  create_table "licensors", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.string "company", null: false
    t.string "contact_name"
    t.string "contact_email"
    t.string "contact_url"
    t.text "notes"
    t.string "next_action"
    t.integer "stage", default: 0, null: false
    t.datetime "last_contacted_at"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "stage", "position"], name: "index_licensors_on_idea_id_and_stage_and_position"
    t.index ["idea_id"], name: "index_licensors_on_idea_id"
    t.index ["stage"], name: "index_licensors_on_stage"
  end

  create_table "lists", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "kind", default: "kanban", null: false
    t.integer "kanban_board_id"
    t.index ["kanban_board_id", "position"], name: "index_lists_on_kanban_board_id_and_position", unique: true, where: "kind = 'kanban'"
    t.index ["kanban_board_id"], name: "index_lists_on_kanban_board_id"
    t.index ["user_id", "kind", "position"], name: "index_lists_on_user_kind_position_named", unique: true, where: "kind = 'named'"
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "maxims", force: :cascade do |t|
    t.text "body"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "media_digests", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "kb_download_id", null: false
    t.string "pipeline", null: false
    t.text "body", null: false
    t.datetime "superseded_at"
    t.integer "superseded_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kb_download_id", "pipeline"], name: "index_media_digests_on_kb_download_id_and_pipeline"
    t.index ["kb_download_id"], name: "index_media_digests_on_kb_download_id"
    t.index ["superseded_at"], name: "index_media_digests_on_superseded_at"
    t.index ["user_id"], name: "index_media_digests_on_user_id"
  end

  create_table "mood_images", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "idea_id"
    t.float "pos_x", default: 0.0, null: false
    t.float "pos_y", default: 0.0, null: false
    t.integer "z_index", default: 0, null: false
    t.string "caption"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id"], name: "index_mood_images_on_idea_id"
    t.index ["user_id", "idea_id"], name: "index_mood_images_on_user_id_and_idea_id"
    t.index ["user_id"], name: "index_mood_images_on_user_id"
  end

  create_table "notes", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.integer "parent_note_id"
    t.text "body", null: false
    t.integer "depth", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "created_at"], name: "index_notes_on_idea_id_and_created_at"
    t.index ["idea_id"], name: "index_notes_on_idea_id"
    t.index ["parent_note_id", "created_at"], name: "index_notes_on_parent_note_id_and_created_at"
    t.index ["parent_note_id"], name: "index_notes_on_parent_note_id"
  end

  create_table "submissions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title", null: false
    t.text "body"
    t.string "source"
    t.string "source_reference"
    t.integer "status", default: 0, null: false
    t.text "raw_data"
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.integer "idea_id"
    t.integer "priority", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "intake_reference", null: false
    t.index ["idea_id"], name: "index_submissions_on_idea_id"
    t.index ["intake_reference"], name: "index_submissions_on_intake_reference", unique: true
    t.index ["reviewed_at"], name: "index_submissions_on_reviewed_at"
    t.index ["source", "source_reference"], name: "index_submissions_on_source_and_source_reference", unique: true
    t.index ["user_id", "status"], name: "index_submissions_on_user_id_and_status"
    t.index ["user_id"], name: "index_submissions_on_user_id"
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
    t.text "scoring_system_ids", default: "[]", null: false
    t.integer "topology_id"
    t.index ["user_id", "is_default"], name: "index_templates_on_user_id_and_is_default"
    t.index ["user_id", "name"], name: "index_templates_on_user_id_and_name", unique: true
    t.index ["user_id", "topology_id"], name: "index_templates_on_user_id_and_topology_id"
    t.index ["user_id"], name: "index_templates_on_user_id"
  end

  create_table "themes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_themes_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_themes_on_user_id"
  end

  create_table "todo_items", force: :cascade do |t|
    t.integer "idea_id", null: false
    t.string "title", null: false
    t.integer "position"
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idea_id", "completed"], name: "index_todo_items_on_idea_id_and_completed"
    t.index ["idea_id", "position"], name: "index_todo_items_on_idea_id_and_position"
    t.index ["idea_id"], name: "index_todo_items_on_idea_id"
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
    t.text "default_field_definitions", default: "[]", null: false
    t.index ["parent_id"], name: "index_topologies_on_parent_id"
    t.index ["user_id", "parent_id", "name"], name: "index_topologies_on_user_id_and_parent_id_and_name", unique: true
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
  add_foreign_key "agent_events", "agent_runs"
  add_foreign_key "agent_events", "users"
  add_foreign_key "agent_recommendations", "agent_events"
  add_foreign_key "agent_recommendations", "users"
  add_foreign_key "agent_runs", "users"
  add_foreign_key "api_keys", "users"
  add_foreign_key "build_items", "users"
  add_foreign_key "capture_jobs", "users"
  add_foreign_key "drawings", "ideas"
  add_foreign_key "export_jobs", "users"
  add_foreign_key "github_repositories", "ideas"
  add_foreign_key "idea_agent_tokens", "ideas"
  add_foreign_key "idea_entries", "ideas"
  add_foreign_key "idea_kb_links", "ideas"
  add_foreign_key "idea_lists", "ideas"
  add_foreign_key "idea_lists", "lists"
  add_foreign_key "idea_themes", "ideas"
  add_foreign_key "idea_themes", "themes"
  add_foreign_key "idea_topologies", "ideas"
  add_foreign_key "idea_topologies", "topologies"
  add_foreign_key "ideas", "templates"
  add_foreign_key "ideas", "users"
  add_foreign_key "kanban_boards", "users"
  add_foreign_key "kb_annotations", "users"
  add_foreign_key "kb_bookmarks", "users"
  add_foreign_key "kb_downloads", "users"
  add_foreign_key "kb_entry_preferences", "users"
  add_foreign_key "kb_fs_jobs", "users"
  add_foreign_key "kb_links", "users"
  add_foreign_key "kb_media_edits", "users"
  add_foreign_key "knowledge_extractions", "ideas"
  add_foreign_key "licensor_contacts", "licensors"
  add_foreign_key "licensor_imports", "ideas"
  add_foreign_key "licensors", "ideas"
  add_foreign_key "lists", "kanban_boards"
  add_foreign_key "lists", "users"
  add_foreign_key "media_digests", "kb_downloads"
  add_foreign_key "media_digests", "users"
  add_foreign_key "mood_images", "ideas"
  add_foreign_key "mood_images", "users"
  add_foreign_key "notes", "ideas"
  add_foreign_key "notes", "notes", column: "parent_note_id"
  add_foreign_key "submissions", "ideas"
  add_foreign_key "submissions", "users"
  add_foreign_key "templates", "users"
  add_foreign_key "themes", "users"
  add_foreign_key "todo_items", "ideas"
  add_foreign_key "topologies", "topologies", column: "parent_id"
  add_foreign_key "topologies", "users"
  add_foreign_key "versions", "ideas"
  add_foreign_key "versions", "versions", column: "parent_version_id"
end
