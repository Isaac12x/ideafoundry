class CreateKbEntryPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_entry_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.text :source_path, null: false, default: ""
      t.text :relative_path, null: false, default: ""
      t.string :entry_type, null: false
      t.boolean :favorite, null: false, default: false
      t.string :icon_kind, null: false, default: "default"
      t.string :emoji

      t.timestamps
    end

    add_index :kb_entry_preferences,
              [:user_id, :source_path, :relative_path, :entry_type],
              unique: true,
              name: "index_kb_entry_preferences_on_entry"
  end
end
