class ScheduledBackupNotificationJob < ApplicationJob
  queue_as :default

  def perform(export_job_id)
    export_job = ExportJob.find_by(id: export_job_id)
    return unless export_job&.completed?

    user = export_job.user
    return unless user

    backup_settings = user.backup_settings
    return unless backup_settings['email_notification'].to_s == 'true'

    recipient = backup_settings['notification_email'].presence || user.email_recipients.first
    return unless recipient.present?

    BackupMailer.backup_completed(user, export_job, recipient).deliver_later
  rescue StandardError => e
    Rails.logger.error("ScheduledBackupNotificationJob failed for export_job #{export_job_id}: #{e.message}")
  end
end
