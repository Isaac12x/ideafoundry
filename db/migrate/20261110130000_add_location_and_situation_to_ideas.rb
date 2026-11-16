class AddLocationAndSituationToIdeas < ActiveRecord::Migration[8.1]
  def change
    add_column :ideas, :location, :string
    add_column :ideas, :latitude, :decimal, precision: 10, scale: 6
    add_column :ideas, :longitude, :decimal, precision: 10, scale: 6
    add_column :ideas, :situation, :text
  end
end
