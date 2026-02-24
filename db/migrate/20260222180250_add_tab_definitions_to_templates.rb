class AddTabDefinitionsToTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :templates, :tab_definitions, :text
  end
end
