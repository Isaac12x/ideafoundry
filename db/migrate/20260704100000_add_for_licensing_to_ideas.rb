class AddForLicensingToIdeas < ActiveRecord::Migration[8.1]
  def change
    add_column :ideas, :for_licensing, :boolean, default: false, null: false
    add_index :ideas, [:user_id, :for_licensing]
  end
end
