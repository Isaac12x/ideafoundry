class CreateIdeaDependencies < ActiveRecord::Migration[8.0]
  def change
    create_table :idea_dependencies do |t|
      t.references :idea, null: false, foreign_key: true                                  # comes AFTER
      t.references :prerequisite, null: false, foreign_key: { to_table: :ideas }          # builds on / requires
      t.timestamps
    end
    add_index :idea_dependencies, [ :idea_id, :prerequisite_id ], unique: true
  end
end
