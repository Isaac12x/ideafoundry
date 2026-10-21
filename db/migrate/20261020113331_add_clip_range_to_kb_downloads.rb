class AddClipRangeToKbDownloads < ActiveRecord::Migration[8.1]
  def change
    add_column :kb_downloads, :clip_start, :integer
    add_column :kb_downloads, :clip_end, :integer
  end
end
