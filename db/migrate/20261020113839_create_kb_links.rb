# One row per alias ("also in") or related link between KB entries.
# alias: source = canonical entry, peer = the slot (folder/name) it is shown at.
# related: source/peer are the two entries (bidirectional; one row per pair).
class CreateKbLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_links do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.text :source_path, null: false
      t.text :relative_path, null: false
      t.text :peer_source_path, null: false
      t.text :peer_relative_path, null: false
      t.timestamps
    end
    add_index :kb_links, %i[user_id kind source_path relative_path peer_source_path peer_relative_path],
              unique: true, name: "index_kb_links_on_pair"
  end
end
