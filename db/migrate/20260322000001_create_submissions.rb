class CreateSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :submissions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body
      t.string :source
      t.string :source_reference
      t.integer :status, default: 0, null: false
      t.text :raw_data
      t.text :review_notes
      t.datetime :reviewed_at
      t.references :idea, null: true, foreign_key: true
      t.integer :priority, default: 1, null: false
      t.timestamps
    end

    add_index :submissions, [:user_id, :status]
    add_index :submissions, [:source, :source_reference], unique: true
    add_index :submissions, :reviewed_at
  end
end
