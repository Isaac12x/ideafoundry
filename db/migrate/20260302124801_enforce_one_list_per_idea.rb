class EnforceOneListPerIdea < ActiveRecord::Migration[8.0]
  def up
    # Remove duplicates — keep the earliest association per idea
    execute <<-SQL
      DELETE FROM idea_lists
      WHERE id NOT IN (
        SELECT MIN(id) FROM idea_lists GROUP BY idea_id
      )
    SQL

    # Remove old compound unique index
    remove_index :idea_lists, [:idea_id, :list_id], if_exists: true

    # Replace non-unique idea_id index with unique one
    remove_index :idea_lists, :idea_id, if_exists: true
    add_index :idea_lists, :idea_id, unique: true
  end

  def down
    remove_index :idea_lists, :idea_id, if_exists: true
    add_index :idea_lists, :idea_id
    add_index :idea_lists, [:idea_id, :list_id], unique: true
  end
end
