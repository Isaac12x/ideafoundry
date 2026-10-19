# Capture requests the IdeaFoundry Chrome extension polls for (see Api::V1::CaptureController).
class CreateCaptureJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :capture_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :url, null: false
      t.string :file_format, null: false, default: "md"
      t.string :state, null: false, default: "queued"
      t.datetime :claimed_at
      t.datetime :finished_at
      t.string :filename
      t.text :error
      t.timestamps
    end
    add_index :capture_jobs, :public_id, unique: true
    add_index :capture_jobs, [ :user_id, :state, :created_at ]
  end
end
