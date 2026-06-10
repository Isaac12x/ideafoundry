class CreateNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :notes do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :parent_note, null: true, foreign_key: { to_table: :notes }
      t.text :body, null: false
      t.integer :depth, default: 0, null: false
      t.timestamps
    end

    add_index :notes, [:idea_id, :created_at]
    add_index :notes, [:parent_note_id, :created_at]
  end
end
