class AddNapkinCalculationsToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :napkin_calculations, :json
  end
end
