class AddActivePathIndexToKbMediaEdits < ActiveRecord::Migration[8.1]
  def change
    add_index :kb_media_edits,
              [:user_id, :source_path, :relative_path],
              unique: true,
              where: "status IN ('pending', 'running')",
              name: "index_active_kb_media_edits_on_path"
  end
end
