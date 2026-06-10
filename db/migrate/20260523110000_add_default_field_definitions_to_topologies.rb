class AddDefaultFieldDefinitionsToTopologies < ActiveRecord::Migration[8.0]
  def change
    add_column :topologies, :default_field_definitions, :text, null: false, default: "[]"
  end
end
