class ScheduledBackupJob < ApplicationJob
  queue_as :default

  def perform
    user = User.first
    return unless user

    settings = user.backup_settings
    return if settings['frequency'] == 'never'
    return unless should_run_today?(settings['frequency'])

    # Skip if there's already an active export
    return if user.export_jobs.where(status: [:pending, :processing]).exists?

    export_job = user.export_jobs.create!
    export_job.start_export!

    enforce_retention(user, settings) if settings['auto_cleanup'].to_s == 'true'

    if settings['email_notification'].to_s == 'true'
      # Wait for export to complete before sending notification
      # The mailer will be triggered after WorkspaceExportJob finishes
      ScheduledBackupNotificationJob.set(wait: 5.minutes).perform_later(export_job.id)
    end
  end

  private

  def should_run_today?(frequency)
    today = Date.current
    case frequency
    when 'daily'   then true
    when 'weekly'  then today.monday?
    when 'monthly' then today.day == 1
    else false
    end
  end

  def enforce_retention(user, settings)
    retention_days = (settings['retention_days'] || 30).to_i
    max_backups = (settings['max_backups'] || 5).to_i

    # Delete exports older than retention period
    user.export_jobs.where('created_at < ?', retention_days.days.ago).find_each do |job|
      job.cleanup_file! if job.file_exists?
      job.destroy!
    end

    # Keep only max_backups most recent
    excess = user.export_jobs.completed.recent.offset(max_backups)
    excess.each do |job|
      job.cleanup_file! if job.file_exists?
      job.destroy!
    end
  end
end
