class RescopeTopologyNameUniquenessToParent < ActiveRecord::Migration[8.0]
  def change
    remove_index :topologies, name: "index_topologies_on_user_id_and_name"
    add_index :topologies, [:user_id, :parent_id, :name], unique: true, name: "index_topologies_on_user_id_and_parent_id_and_name"
  end
end
