class AddDiscardedAtToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :discarded_at, :datetime
    add_index :ideas, :discarded_at
  end
end
