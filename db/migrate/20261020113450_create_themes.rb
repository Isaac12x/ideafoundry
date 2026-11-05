class CreateThemes < ActiveRecord::Migration[8.1]
  def change
    create_table :themes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color
      t.timestamps
    end
    add_index :themes, [ :user_id, :name ], unique: true

    create_table :idea_themes do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :theme, null: false, foreign_key: true
      t.timestamps
    end
    add_index :idea_themes, [ :idea_id, :theme_id ], unique: true
  end
end
