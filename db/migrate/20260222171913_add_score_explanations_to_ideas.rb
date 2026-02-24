class AddScoreExplanationsToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :difficulty_explanation, :text
    add_column :ideas, :opportunity_explanation, :text
    add_column :ideas, :timing_explanation, :text
  end
end
