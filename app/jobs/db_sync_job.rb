class DbSyncJob < ApplicationJob
  queue_as :default

  def perform
    app_dir = Rails.root
    production_db = app_dir.join("storage", "production.sqlite3")
    development_db = app_dir.join("storage", "development.sqlite3")

    unless File.exist?(production_db)
      Rails.logger.warn "[DbSync] production.sqlite3 not found, skipping"
      return
    end

    # Use VACUUM INTO for a safe, consistent snapshot while production is live
    tmp = development_db.sub_ext(".sqlite3.tmp")
    system("sqlite3", production_db.to_s, "VACUUM INTO '#{tmp}';", exception: true)

    FileUtils.mv(tmp, development_db, force: true)
    Rails.logger.info "[DbSync] Synced production → development.sqlite3"
  rescue => e
    FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    Rails.logger.error "[DbSync] Failed: #{e.message}"
    raise
  end
end
