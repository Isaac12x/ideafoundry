class AddSourcePathToKbDownloads < ActiveRecord::Migration[8.1]
  def change
    add_column :kb_downloads, :source_path, :text
  end
end
