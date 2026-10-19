class AddTargetToCaptureJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :capture_jobs, :source_index, :integer
    add_column :capture_jobs, :dir, :string
  end
end
