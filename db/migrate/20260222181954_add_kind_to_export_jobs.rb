class AddKindToExportJobs < ActiveRecord::Migration[8.0]
  def change
    add_column :export_jobs, :kind, :integer, default: 0, null: false
  end
end
