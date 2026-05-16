class RescopeDrawingsToIdeas < ActiveRecord::Migration[8.0]
  def up
    drop_table :drawings if table_exists?(:drawings)
    create_table :drawings do |t|
      t.references :idea, null: false, foreign_key: true
      t.string :title, null: false
      t.text :content, null: false
      t.timestamps
    end
    add_index :drawings, [:idea_id, :updated_at]
  end

  def down
    drop_table :drawings
    create_table :drawings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :content, null: false
      t.timestamps
    end
    add_index :drawings, [:user_id, :updated_at]
  end
end
