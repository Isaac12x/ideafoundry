class CreateMaxims < ActiveRecord::Migration[8.0]
  def change
    create_table :maxims do |t|
      t.text :body
      t.integer :user_id

      t.timestamps
    end
  end
end
