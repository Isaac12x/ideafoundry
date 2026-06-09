class AddKindToListsAndRelaxIdeaListMembership < ActiveRecord::Migration[8.0]
  def up
    add_column :lists, :kind, :string, default: "kanban", null: false unless column_exists?(:lists, :kind)

    remove_index :lists, [:user_id, :position], if_exists: true
    add_index :lists, [:user_id, :kind, :position], unique: true, if_not_exists: true

    remove_index :idea_lists, :idea_id, if_exists: true
    add_index :idea_lists, [:idea_id, :list_id], unique: true, if_not_exists: true
  end

  def down
    remove_index :idea_lists, [:idea_id, :list_id], if_exists: true
    add_index :idea_lists, :idea_id, unique: true, if_not_exists: true

    remove_index :lists, [:user_id, :kind, :position], if_exists: true
    add_index :lists, [:user_id, :position], unique: true, if_not_exists: true

    remove_column :lists, :kind if column_exists?(:lists, :kind)
  end
end
