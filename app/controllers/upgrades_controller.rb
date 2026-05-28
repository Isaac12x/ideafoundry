class UpgradesController < ApplicationController
  UPGRADE_LOCK_FILE = Rails.root.join("tmp", "upgrade.lock").freeze

  before_action :require_local_request

  def create
    return render json: { status: "upgrading" }, status: :accepted if upgrading?

    FileUtils.touch(UPGRADE_LOCK_FILE)
    Thread.new { run_upgrade }
    render json: { status: "upgrading" }, status: :accepted
  end

  def status
    if upgrading?
      render json: { status: "upgrading" }
    else
      render json: { status: "idle" }
    end
  end

  private

  def require_local_request
    return if request.local?
    render json: { error: "forbidden" }, status: :forbidden
  end

  def upgrading?
    UPGRADE_LOCK_FILE.exist?
  end

  def run_upgrade
    steps = [
      "git fetch origin && git reset --hard origin/master",
      "BUNDLE_WITHOUT='development:test' bundle install --quiet",
      "bin/rails assets:precompile RAILS_ENV=production",
      "bin/rails db:migrate RAILS_ENV=production"
    ]

    steps.each do |cmd|
      unless system(cmd)
        Rails.logger.error("[Upgrade] Command failed: #{cmd}")
        return
      end
    end
  rescue => e
    Rails.logger.error("[Upgrade] Unexpected error: #{e.message}")
  ensure
    user = User.first
    if user
      user.settings ||= {}
      user.settings.delete("upgrade")
      user.save
    end
    pid_file = Rails.root.join("tmp", "pids", "server.pid")
    if pid_file.exist?
      pid = pid_file.read.strip.to_i
      Process.kill("TERM", pid) if pid > 0
    end
    UPGRADE_LOCK_FILE.delete if UPGRADE_LOCK_FILE.exist?
  end
end
