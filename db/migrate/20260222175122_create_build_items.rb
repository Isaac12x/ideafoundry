class CreateBuildItems < ActiveRecord::Migration[8.0]
  def change
    create_table :build_items do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :position
      t.boolean :completed, default: false, null: false
      t.datetime :completed_at

      t.timestamps
    end
    add_index :build_items, [:user_id, :position]
    add_index :build_items, [:user_id, :completed]
  end
end
