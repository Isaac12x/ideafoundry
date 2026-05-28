class AddTldrToIdeas < ActiveRecord::Migration[7.1]
  def change
    add_column :ideas, :tldr, :string
  end
end
