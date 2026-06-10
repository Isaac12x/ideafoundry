Rails.application.config.app_version = `git describe --tags --abbrev=0 2>/dev/null`.strip.presence || "v0.0.0"
