class RemoveClustersEntirely < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :ideas, :clusters
    remove_index :ideas, :cluster_id
    remove_column :ideas, :cluster_id, :integer
    remove_column :ideas, :cluster_x, :decimal
    remove_column :ideas, :cluster_y, :decimal
    drop_table :clusters do |t|
      t.string "name", null: false
      t.string "cluster_type"
      t.integer "user_id", null: false
      t.integer "position"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["user_id", "cluster_type"]
      t.index ["user_id", "position"]
      t.index ["user_id"]
    end
  end
end
