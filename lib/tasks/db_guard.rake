# DATABASE_URL only overrides the primary config, so a "scratch" schema:load in
# development still wipes the queue/cache DBs. Destructive db tasks abort in
# development unless ALLOW_DEV_DB_WIPE=1 (use only on throwaway files). With
# DATABASE_URL set they always abort: the opt-in cannot make that safe.
wipe_task = /\Adb:(schema:load|reset|drop|purge|setup|truncate_all|seed:replant|migrate:reset|fixtures:load)(:|\z)/

namespace :db do
  task :dev_wipe_guard do
    next unless Rails.env.development?

    files = ActiveRecord::Base.configurations.configs_for(env_name: "development").map(&:database)
    if ENV["DATABASE_URL"].present?
      abort "Refusing destructive db task in development with DATABASE_URL set (ALLOW_DEV_DB_WIPE does not apply).\n" \
            "DATABASE_URL only overrides primary; queue/cache would still hit:\n  #{files.join("\n  ")}\n" \
            "Use a worktree instead."
    end
    next if ENV["ALLOW_DEV_DB_WIPE"] == "1"

    abort "Refusing destructive db task in development; it would hit:\n  #{files.join("\n  ")}\n" \
          "Use a worktree, or set ALLOW_DEV_DB_WIPE=1 for throwaway files only."
  end
end

Rake::Task.tasks.select { |t| t.name.match?(wipe_task) }.each do |t|
  t.enhance([ "db:dev_wipe_guard" ])
end
