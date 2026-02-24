class CreateIdeaLists < ActiveRecord::Migration[8.0]
  def change
    create_table :idea_lists do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :list, null: false, foreign_key: true
      t.integer :position

      t.timestamps
    end
    
    add_index :idea_lists, [:idea_id, :list_id], unique: true
    add_index :idea_lists, [:list_id, :position]
  end
end
