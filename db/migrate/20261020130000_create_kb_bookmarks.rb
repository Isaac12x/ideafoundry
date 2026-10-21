class CreateKbBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :source_path, null: false
      t.string :relative_path, null: false
      t.string :label, null: false
      t.integer :page
      t.string :cfi
      t.float :progress
      t.timestamps
    end
    add_index :kb_bookmarks, [ :user_id, :source_path, :relative_path ], name: "index_kb_bookmarks_on_user_and_path"
  end
end
