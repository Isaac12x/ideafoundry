class CreateAgentThreads < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_threads do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.timestamps
    end
    add_index :agent_threads, [ :user_id, :updated_at ]
    add_reference :agent_events, :agent_thread, foreign_key: true
  end
end
