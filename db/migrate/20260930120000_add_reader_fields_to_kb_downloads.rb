class AddReaderFieldsToKbDownloads < ActiveRecord::Migration[8.1]
  def change
    add_column :kb_downloads, :title, :string
    add_column :kb_downloads, :reference_list, :text
    add_column :kb_downloads, :references_state, :string
    add_column :kb_downloads, :archive_url, :string
    add_column :kb_downloads, :attempts, :integer, default: 0, null: false
  end
end
