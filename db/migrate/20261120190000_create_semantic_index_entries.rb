class CreateSemanticIndexEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :semantic_index_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.string :doc_id, null: false
      t.string :sig, null: false
      t.timestamps
    end
    add_index :semantic_index_entries, %i[user_id doc_id], unique: true
  end
end
