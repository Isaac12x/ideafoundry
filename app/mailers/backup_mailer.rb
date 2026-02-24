class BackupMailer < ApplicationMailer
  def backup_completed(user, export_job, recipient_email)
    @user = user
    @export_job = export_job

    mail(
      to: recipient_email,
      subject: "Backup completed — #{export_job.file_size_human}"
    )
  end
end
