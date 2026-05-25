class CreateLocalAgentRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :pid
      t.datetime :started_at
      t.datetime :stopped_at
      t.datetime :last_heartbeat_at
      t.text :metadata
      t.timestamps
    end

    add_index :agent_runs, [:user_id, :status]
    add_index :agent_runs, [:user_id, :last_heartbeat_at]

    create_table :agent_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :agent_run, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :target_type
      t.integer :target_id
      t.text :summary
      t.text :payload
      t.timestamps
    end

    add_index :agent_events, [:user_id, :event_type]
    add_index :agent_events, [:target_type, :target_id]

    create_table :agent_recommendations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :agent_event, null: true, foreign_key: true
      t.string :target_type
      t.integer :target_id
      t.string :action, null: false
      t.string :risk_level, null: false, default: "medium"
      t.text :reasoning
      t.text :payload
      t.integer :status, null: false, default: 0
      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :agent_recommendations, [:user_id, :status]
    add_index :agent_recommendations, [:target_type, :target_id]
    add_index :agent_recommendations, :action
  end
end
