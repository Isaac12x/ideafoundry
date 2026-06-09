class CreateIdeaEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :idea_entries do |t|
      t.references :idea, null: false, foreign_key: true
      t.integer :kind, null: false
      t.string :name, null: false
      t.string :url
      t.text :description
      t.integer :position
      t.timestamps
    end

    add_index :idea_entries, [:idea_id, :kind]
    add_index :idea_entries, [:idea_id, :kind, :position]
  end
end
