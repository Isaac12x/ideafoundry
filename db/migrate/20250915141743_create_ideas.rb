class CreateIdeas < ActiveRecord::Migration[8.0]
  def change
    create_table :ideas do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.integer :state
      t.string :category
      t.integer :trl
      t.integer :difficulty
      t.integer :opportunity
      t.integer :timing
      t.decimal :computed_score
      t.integer :attempt_count
      t.datetime :cool_off_until
      t.decimal :cluster_x
      t.decimal :cluster_y

      t.timestamps
    end
    
    add_index :ideas, :state
    add_index :ideas, :category
    add_index :ideas, :computed_score
    add_index :ideas, :cool_off_until
  end
end
