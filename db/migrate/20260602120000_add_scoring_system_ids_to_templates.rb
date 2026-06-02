class AddScoringSystemIdsToTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :templates, :scoring_system_ids, :text, null: false, default: "[]"
  end
end
