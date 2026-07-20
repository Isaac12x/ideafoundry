class CreateKbFsJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_fs_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :source_index, null: false
      t.text :source_path, null: false
      t.text :context_path, null: false
      t.string :context_kind, null: false
      t.text :target_dir, null: false, default: ""
      t.text :prompt
      t.text :transcript
      t.string :status, null: false, default: "pending"
      t.text :result_path
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :kb_fs_jobs, [:user_id, :status]
  end
end
