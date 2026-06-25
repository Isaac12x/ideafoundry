class AddCategoryToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :category, :string
  end
end
