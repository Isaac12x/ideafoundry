class AddTranscriptToKbDownloads < ActiveRecord::Migration[8.1]
  def change
    add_column :kb_downloads, :video_id, :string
    add_column :kb_downloads, :transcript, :text
    add_column :kb_downloads, :transcript_status, :string
    add_column :kb_downloads, :transcript_attempts, :integer, default: 0, null: false
    add_column :kb_downloads, :transcript_error, :string
    add_index :kb_downloads, :transcript_status
  end
end
