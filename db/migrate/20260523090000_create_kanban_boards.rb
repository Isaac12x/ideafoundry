class CreateKanbanBoards < ActiveRecord::Migration[8.0]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationKanbanBoard < ActiveRecord::Base
    self.table_name = "kanban_boards"
  end

  class MigrationList < ActiveRecord::Base
    self.table_name = "lists"
  end

  def up
    create_table :kanban_boards do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false
      t.timestamps
    end

    add_index :kanban_boards, [:user_id, :position], unique: true
    add_reference :lists, :kanban_board, foreign_key: true

    backfill_default_boards

    remove_index :lists, [:user_id, :kind, :position], if_exists: true
    add_index :lists, [:kanban_board_id, :position],
      unique: true,
      where: "kind = 'kanban'",
      name: "index_lists_on_kanban_board_id_and_position"
    add_index :lists, [:user_id, :kind, :position],
      unique: true,
      where: "kind = 'named'",
      name: "index_lists_on_user_kind_position_named"
  end

  def down
    remove_index :lists, name: "index_lists_on_user_kind_position_named", if_exists: true
    remove_index :lists, name: "index_lists_on_kanban_board_id_and_position", if_exists: true
    remove_reference :lists, :kanban_board, foreign_key: true
    drop_table :kanban_boards

    add_index :lists, [:user_id, :kind, :position], unique: true, if_not_exists: true
  end

  private

  def backfill_default_boards
    now = Time.current

    MigrationUser.find_each do |user|
      kanban_lists = MigrationList.where(user_id: user.id, kind: "kanban").order(:position, :id)
      next unless kanban_lists.exists?

      board = MigrationKanbanBoard.create!(
        user_id: user.id,
        name: "Main Board",
        position: 1,
        created_at: now,
        updated_at: now
      )

      kanban_lists.update_all(kanban_board_id: board.id, updated_at: now)
    end
  end
end
