class CreateProblems < ActiveRecord::Migration[8.0]
  def change
    create_table :problems do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :need
      t.string :folder, null: false
      t.string :status, null: false, default: "pending"
      t.string :result
      t.timestamps
    end
    add_index :problems, %i[user_id folder], unique: true
  end
end
