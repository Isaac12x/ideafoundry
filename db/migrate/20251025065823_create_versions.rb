class CreateVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :versions do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :parent_version, null: true, foreign_key: { to_table: :versions }
      t.text :commit_message, null: false
      t.text :snapshot_data, null: false
      t.text :diff_summary

      t.timestamps
    end
    
    add_index :versions, [:idea_id, :created_at]
  end
end
