class CreateNotificationsAndScopeTodoItems < ActiveRecord::Migration[8.0]
  def change
    # Scope = general (idea_id and project_path NULL), per idea, or per KB project (project_src + project_path).
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :idea, foreign_key: true
      t.string :project_src
      t.string :project_path
      t.string :title, null: false
      t.text :body
      t.string :url
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [ :user_id, :read_at ]

    # Tasks reuse todo_items: idea tasks keep idea_id, general/project tasks have none.
    change_column_null :todo_items, :idea_id, true
    add_reference :todo_items, :user, foreign_key: true
    add_column :todo_items, :project_src, :string
    add_column :todo_items, :project_path, :string
  end
end
