# Destructive db tasks abort unless every config of the env is a plain test DB
# (DbWipeGuard.test_db?). No opt-in; DISABLE_DATABASE_ENVIRONMENT_CHECK is moot.
# Same refusal lives below rake in config/initializers/db_wipe_guard.rb.
# Forward tasks stay open: db:prepare, db:migrate, db:migrate:up, db:create, db:seed, db:schema:dump, db:test:*.
# Down-migrations (rollback/redo/reset, VERSION < current) run `down` bodies that drop tables, so they are wiped too.
wipe_task = /\Adb:(schema:load|reset|drop|purge|setup|truncate_all|seed:replant|migrate:(reset|redo|down)|rollback|fixtures:load)(:|\z)/

namespace :db do
  task :wipe_guard do
    configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
    next if configs.any? && configs.all? { |c| DbWipeGuard.test_db?(c) }

    files = configs.map(&:database)
    abort "Refusing destructive db task in #{Rails.env}: databases are never wiped. No opt-in exists " \
          "(DISABLE_DATABASE_ENVIRONMENT_CHECK / DATABASE_URL change nothing).\n  #{files.join("\n  ")}\n" \
          "Tests reset themselves (bin/rails test); use a separate worktree for scratch work."
  end

  # db:migrate VERSION=0 (or any VERSION below current) migrates down.
  task :migrate_down_guard do
    next if ENV["VERSION"].blank?

    current = ActiveRecord::Base.connection_pool.migration_context.current_version
    Rake::Task["db:wipe_guard"].invoke if ENV["VERSION"].to_i < current
  end
end

Rake::Task.tasks.select { |t| t.name.match?(wipe_task) }.each { |t| t.prerequisites.unshift("db:wipe_guard") }
Rake::Task["db:migrate"].prerequisites << "db:migrate_down_guard"
