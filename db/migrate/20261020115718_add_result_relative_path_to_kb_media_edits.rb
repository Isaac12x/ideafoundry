class AddResultRelativePathToKbMediaEdits < ActiveRecord::Migration[8.1]
  def change
    add_column :kb_media_edits, :result_relative_path, :string
  end
end
