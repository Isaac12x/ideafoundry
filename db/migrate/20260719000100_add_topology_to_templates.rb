class AddTopologyToTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :templates, :topology_id, :integer
    add_index :templates, [:user_id, :topology_id]
  end
end
