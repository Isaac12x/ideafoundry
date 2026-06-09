class AddDraftToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :draft, :boolean, default: false, null: false
    add_index :ideas, [:user_id, :draft]
  end
end
