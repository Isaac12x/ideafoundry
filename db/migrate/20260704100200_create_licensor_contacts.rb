class CreateLicensorContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :licensor_contacts do |t|
      t.references :licensor, null: false, foreign_key: true
      t.datetime :occurred_at, null: false
      t.integer :channel, null: false, default: 0
      t.text :summary

      t.timestamps
    end

    add_index :licensor_contacts, [:licensor_id, :occurred_at]
  end
end
