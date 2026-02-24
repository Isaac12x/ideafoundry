class ScheduledBackupNotificationJob < ApplicationJob
  queue_as :default

  def perform(export_job_id)
    export_job = ExportJob.find_by(id: export_job_id)
    return unless export_job&.completed?

    user = export_job.user
    recipients = user.email_recipients
    return if recipients.empty?

    recipients.each do |email|
      BackupMailer.backup_completed(user, export_job, email).deliver_later
    end
  end
end
