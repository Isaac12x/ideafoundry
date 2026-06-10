class AddRoleAndPositionToDrawings < ActiveRecord::Migration[8.0]
  def change
    add_column :drawings, :role, :integer, default: 0, null: false
    add_column :drawings, :position, :integer
    add_index :drawings, [:idea_id, :role, :position]
  end
end
