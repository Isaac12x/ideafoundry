class CreateMoodImages < ActiveRecord::Migration[8.1]
  def change
    create_table :mood_images do |t|
      t.references :user, null: false, foreign_key: true
      # null idea_id = the global "Think in Images" board shown in the KB tab.
      t.references :idea, null: true, foreign_key: true
      t.float :pos_x, null: false, default: 0
      t.float :pos_y, null: false, default: 0
      t.integer :z_index, null: false, default: 0
      t.string :caption

      t.timestamps
    end

    add_index :mood_images, %i[user_id idea_id]
  end
end
