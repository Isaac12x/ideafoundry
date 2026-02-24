class AddTemplateAndMetadataToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_reference :ideas, :template, null: true, foreign_key: true
    add_column :ideas, :metadata, :text
  end
end
