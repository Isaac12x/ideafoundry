class CreateKbAnnotations < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_annotations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :source_path, null: false
      t.string :relative_path, null: false
      t.string :style, null: false, default: "highlight"
      t.string :color, null: false, default: "yellow"
      t.integer :page
      t.integer :start_offset, null: false
      t.integer :end_offset, null: false
      t.text :quote, null: false
      t.string :prefix, null: false, default: ""
      t.string :suffix, null: false, default: ""
      t.timestamps
    end
    add_index :kb_annotations, [:user_id, :source_path, :relative_path], name: "index_kb_annotations_on_user_and_path"
  end
end
