class CreateIdeaKbLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :idea_kb_links do |t|
      t.references :idea, null: false, foreign_key: true
      t.string :source_path, null: false
      t.string :relative_path, null: false, default: ""
      t.string :entry_type, null: false, default: "file"
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :idea_kb_links, [:idea_id, :source_path, :relative_path], unique: true, name: "index_idea_kb_links_uniqueness"
    add_index :idea_kb_links, [:source_path, :relative_path]
  end
end
