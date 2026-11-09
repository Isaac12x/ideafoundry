# Which scoring system drives an idea's weighted score; nil keeps the average of all enabled systems.
class AddPrimaryScoringSystemIdToTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :templates, :primary_scoring_system_id, :string
  end
end
