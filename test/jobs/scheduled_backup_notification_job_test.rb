require "test_helper"

class ScheduledBackupNotificationJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
    @export_job = @user.export_jobs.create!(status: :completed, progress: 100, file_path: "/tmp/test_backup.tar.gz")
  end

  test "sends backup notification email when export is completed" do
    @user.settings ||= {}
    @user.settings["backup"] = {
      "frequency" => "daily",
      "email_notification" => "true",
      "notification_email" => "test@example.com"
    }
    @user.save!

    assert_enqueued_emails 1 do
      ScheduledBackupNotificationJob.perform_now(@export_job.id)
    end
  end

  test "skips notification when email_notification is disabled" do
    @user.settings ||= {}
    @user.settings["backup"] = { "email_notification" => "false" }
    @user.save!

    assert_no_enqueued_emails do
      ScheduledBackupNotificationJob.perform_now(@export_job.id)
    end
  end

  test "skips notification when export job is not completed" do
    failed_job = @user.export_jobs.create!(status: :failed, progress: 50)
    @user.settings ||= {}
    @user.settings["backup"] = { "email_notification" => "true" }
    @user.save!

    assert_no_enqueued_emails do
      ScheduledBackupNotificationJob.perform_now(failed_job.id)
    end
  end

  test "handles missing export job gracefully" do
    assert_nothing_raised do
      ScheduledBackupNotificationJob.perform_now(999999)
    end
  end
end
