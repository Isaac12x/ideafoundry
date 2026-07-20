class AddVersioningToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :version_group_id, :integer
    add_column :ideas, :version_number, :integer
    add_column :ideas, :version_primary, :boolean, default: false, null: false
    add_index :ideas, :version_group_id
  end
end
