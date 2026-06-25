class AddPinnedToBuildItems < ActiveRecord::Migration[8.0]
  def change
    add_column :build_items, :pinned, :boolean, null: false, default: false
    add_index :build_items, [:user_id, :pinned, :position], name: "index_build_items_on_user_id_and_pinned_and_position"
  end
end
