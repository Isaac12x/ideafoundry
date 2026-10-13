class AddOpenedAtToKbDownloads < ActiveRecord::Migration[8.1]
  def up
    add_column :kb_downloads, :opened_at, :datetime
    # Existing downloads count as seen so they don't light up.
    execute "UPDATE kb_downloads SET opened_at = CURRENT_TIMESTAMP WHERE status = 'done'"
  end

  def down
    remove_column :kb_downloads, :opened_at
  end
end
