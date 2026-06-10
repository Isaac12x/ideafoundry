class CreateTodoItems < ActiveRecord::Migration[8.0]
  def change
    create_table :todo_items do |t|
      t.references :idea, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position
      t.boolean :completed, default: false, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :todo_items, [:idea_id, :completed]
    add_index :todo_items, [:idea_id, :position]
  end
end
