class CreateLists < ActiveRecord::Migration[8.0]
  def change
    create_table :lists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.integer :position

      t.timestamps
    end
    
    add_index :lists, [:user_id, :position], unique: true
  end
end
