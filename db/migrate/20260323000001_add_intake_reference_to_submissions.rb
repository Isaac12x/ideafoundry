class AddIntakeReferenceToSubmissions < ActiveRecord::Migration[8.0]
  class MigrationSubmission < ApplicationRecord
    self.table_name = "submissions"
  end

  def up
    add_column :submissions, :intake_reference, :string
    add_index :submissions, :intake_reference, unique: true

    MigrationSubmission.reset_column_information

    MigrationSubmission.find_each do |submission|
      submission.update_columns(intake_reference: build_reference(submission))
    end

    change_column_null :submissions, :intake_reference, false
  end

  def down
    remove_index :submissions, :intake_reference
    remove_column :submissions, :intake_reference
  end

  private

  def build_reference(submission)
    date = (submission.created_at || Time.current).strftime("%Y%m%d")
    "IDEA-TMP-#{date}-#{submission.id.to_s.rjust(4, "0")}"
  end
end
