class CreateKbMediaEdits < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_media_edits do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :source_index, null: false
      t.string :source_path, null: false
      t.string :relative_path, null: false
      t.string :media_kind, null: false
      t.string :status, null: false, default: "pending"
      t.text :operations
      t.string :original_sha256
      t.string :result_sha256
      t.string :revision_path
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :kb_media_edits, [:user_id, :status]
    add_index :kb_media_edits, [:source_path, :relative_path]
  end
end
