class CreateClusters < ActiveRecord::Migration[8.0]
  def change
    create_table :clusters do |t|
      t.string :name, null: false
      t.string :cluster_type # 'tag', 'type', 'category', 'similarity', 'manual'
      t.references :user, null: false, foreign_key: true
      t.integer :position

      t.timestamps
    end

    add_index :clusters, [:user_id, :position]
    add_index :clusters, [:user_id, :cluster_type]

    add_reference :ideas, :cluster, foreign_key: true
  end
end
