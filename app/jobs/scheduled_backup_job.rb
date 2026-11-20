class ScheduledBackupJob < ApplicationJob
  queue_as :default

  def perform
    user = User.first
    return unless user

    settings = user.backup_settings
    return if settings["frequency"] == "never"
    return unless should_run_today?(settings["frequency"])

    # Skip if there's already an active export
    return if user.export_jobs.where(status: [ :pending, :processing ]).exists?

    export_job = user.export_jobs.create!(kind: :backup)
    export_job.start_export!

    if settings["email_notification"].to_s == "true"
      # Wait for export to complete before sending notification
      # The mailer will be triggered after WorkspaceExportJob finishes
      ScheduledBackupNotificationJob.set(wait: 5.minutes).perform_later(export_job.id)
    end
  end

  private

  def should_run_today?(frequency)
    today = Date.current
    case frequency
    when "daily"   then true
    when "weekly"  then today.monday?
    when "monthly" then today.day == 1
    else false
    end
  end

  def self.enforce_retention(user, settings, keep_job_id:)
    retention_days = (settings["retention_days"] || 30).to_i
    max_backups = [ (settings["max_backups"] || 5).to_i, 1 ].max
    retired_paths = ExportJob.transaction do
      completed_backups = user.export_jobs.backups.completed
      next [] unless completed_backups.exists?(keep_job_id)

      paths = []
      # Delete backups older than retention period
      completed_backups.where("created_at < ?", retention_days.days.ago).where.not(id: keep_job_id).find_each do |job|
        paths << retire_backup(job)
      end

      # Keep only max_backups most recent, with the just-completed backup protected.
      excess = completed_backups.where.not(id: keep_job_id).recent.offset(max_backups - 1)
      excess.each do |job|
        paths << retire_backup(job)
      end
      paths.compact.uniq
    end

    # Do filesystem cleanup only after database changes commit. Recheck references
    # so a path shared with another export is never removed.
    retired_paths.each do |file_path|
      FileUtils.rm_f(file_path) unless ExportJob.where(file_path: file_path).exists?
    end
  end

  def self.retire_backup(job)
    file_path = job.file_path
    job.destroy!
    file_path
  end
  private_class_method :retire_backup
end
