# Hidden, agent-only distillations of KB media ("facts"). Never shown in the KB.
# Each row is one pipeline's output for one download; a better pipeline later
# writes a new row and supersedes the old one (superseded_at/superseded_by_id).
class CreateMediaDigests < ActiveRecord::Migration[8.1]
  def change
    create_table :media_digests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :kb_download, null: false, foreign_key: true
      t.string :pipeline, null: false
      t.text :body, null: false
      t.datetime :superseded_at
      t.integer :superseded_by_id
      t.timestamps
    end
    add_index :media_digests, [ :kb_download_id, :pipeline ]
    add_index :media_digests, :superseded_at
  end
end
