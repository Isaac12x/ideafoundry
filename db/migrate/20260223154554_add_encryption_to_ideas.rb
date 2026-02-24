class AddEncryptionToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :email_ingested, :boolean, default: false, null: false
    add_column :ideas, :integrity_hash, :string
    add_index :ideas, :integrity_hash
  end
end
