class CreateLicensorImports < ActiveRecord::Migration[8.1]
  def change
    create_table :licensor_imports do |t|
      t.references :idea, null: false, foreign_key: true
      t.string  :filename, null: false
      t.string  :status, null: false, default: "pending"
      t.text    :column_mapping
      t.boolean :headers_in_first_row, null: false, default: true
      t.integer :imported_count, null: false, default: 0
      t.integer :row_count, null: false, default: 0
      t.timestamps
    end
  end
end
