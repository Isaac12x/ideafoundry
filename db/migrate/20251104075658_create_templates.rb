class CreateTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :templates do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :is_default, default: false, null: false
      t.text :field_definitions, null: false
      t.text :section_order, null: false

      t.timestamps
    end

    add_index :templates, [:user_id, :name], unique: true
    add_index :templates, [:user_id, :is_default]
  end
end
