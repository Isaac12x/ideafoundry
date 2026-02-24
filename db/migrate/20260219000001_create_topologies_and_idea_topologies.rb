class CreateTopologiesAndIdeaTopologies < ActiveRecord::Migration[8.0]
  def up
    # Create topologies table
    create_table :topologies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :parent, null: true, foreign_key: { to_table: :topologies }
      t.string :name, null: false
      t.integer :topology_type, default: 1, null: false # 0=predefined, 1=custom
      t.string :color
      t.integer :position

      t.timestamps
    end

    add_index :topologies, [:user_id, :parent_id]
    add_index :topologies, [:user_id, :name], unique: true

    # Create join table
    create_table :idea_topologies do |t|
      t.references :idea, null: false, foreign_key: true
      t.references :topology, null: false, foreign_key: true

      t.timestamps
    end

    add_index :idea_topologies, [:idea_id, :topology_id], unique: true

    # Migrate existing category data
    execute <<-SQL
      INSERT INTO topologies (user_id, name, topology_type, created_at, updated_at)
      SELECT DISTINCT i.user_id, i.category, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM ideas i
      WHERE i.category IS NOT NULL AND i.category != ''
    SQL

    execute <<-SQL
      INSERT INTO idea_topologies (idea_id, topology_id, created_at, updated_at)
      SELECT i.id, t.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM ideas i
      INNER JOIN topologies t ON t.user_id = i.user_id AND t.name = i.category
      WHERE i.category IS NOT NULL AND i.category != ''
    SQL

    # Remove category column and its index
    remove_index :ideas, :category
    remove_column :ideas, :category
  end

  def down
    add_column :ideas, :category, :string
    add_index :ideas, :category

    # Restore category from first topology association
    execute <<-SQL
      UPDATE ideas SET category = (
        SELECT t.name FROM topologies t
        INNER JOIN idea_topologies it ON it.topology_id = t.id
        WHERE it.idea_id = ideas.id
        LIMIT 1
      )
    SQL

    drop_table :idea_topologies
    drop_table :topologies
  end
end
