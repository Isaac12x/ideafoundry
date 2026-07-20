class CreateKbDownloads < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_downloads do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :source_index, null: false
      t.string :dir, null: false, default: ""
      t.string :url, null: false
      t.string :format, null: false, default: "auto"   # auto | video | audio
      t.string :status, null: false, default: "pending" # pending | running | done | failed
      t.string :filename
      t.text :error

      t.timestamps
    end

    add_index :kb_downloads, %i[user_id status]
  end
end
