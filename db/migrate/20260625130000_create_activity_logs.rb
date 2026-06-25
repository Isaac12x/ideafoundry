class CreateActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_logs do |t|
      t.integer  :user_id,        null: false
      t.string   :actor,          null: false, default: "user"
      t.string   :action,         null: false
      t.string   :trackable_type
      t.integer  :trackable_id
      t.string   :trackable_name
      t.text     :details
      t.datetime :created_at,     null: false
    end

    add_index :activity_logs, [:user_id, :created_at]
    add_index :activity_logs, [:trackable_type, :trackable_id]
  end
end
