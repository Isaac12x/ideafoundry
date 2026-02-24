class CreateExportJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :export_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :progress, null: false, default: 0
      t.string :file_path
      t.boolean :password_protected, null: false, default: false
      t.text :error_message

      t.timestamps
    end

    add_index :export_jobs, [:user_id, :status]
    add_index :export_jobs, :created_at
  end
end
