class CreateFacts < ActiveRecord::Migration[8.0]
  def change
    create_table :facts do |t|
      t.text :body
      t.integer :user_id

      t.timestamps
    end
  end
end
