class CreateLicensors < ActiveRecord::Migration[8.1]
  def change
    create_table :licensors do |t|
      t.references :idea, null: false, foreign_key: true
      t.string :company, null: false
      t.string :contact_name
      t.string :contact_email
      t.string :contact_url
      t.text :notes
      t.string :next_action
      t.integer :stage, null: false, default: 0
      t.datetime :last_contacted_at
      t.integer :position

      t.timestamps
    end

    add_index :licensors, [:idea_id, :stage, :position]
    add_index :licensors, :stage
  end
end
