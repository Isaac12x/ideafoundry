# Databases hold people's life's work: nothing may drop, purge, truncate or overwrite one
# unless it is a plain test DB (see test_db?). No env var, no opt-in. Covers rake, runner,
# console and app code alike; lib/tasks/db_guard.rake is the friendlier first layer.
module DbWipeGuard
  class Refused < StandardError; end

  def drop(configuration, *)                = DbWipeGuard.deny!(:drop, resolve_configuration(configuration)) && super
  def purge(configuration)                  = DbWipeGuard.deny!(:purge, resolve_configuration(configuration)) && super
  def reconstruct_from_schema(db_config, *) = DbWipeGuard.deny!(:reconstruct_from_schema, db_config) && super

  def truncate_all(environment = env)
    DbWipeGuard.deny!(:truncate_all, environment) && super
  end

  # Loading a schema into a fresh, empty DB is what db:prepare does; into a non-empty one it is a wipe.
  def load_schema(db_config, *)
    DbWipeGuard.deny!(:load_schema, db_config) unless DbWipeGuard.empty?(db_config, self)
    super
  end

  # Exempt only when env is "test" AND every target file is plainly a test DB AND
  # DATABASE_URL is unset (it can repoint a "test" config at a real file).
  TEST_FILE = /(^|[_.-])test([_.-]|$)/
  REAL_FILE = /development|production|\Aqueue\.|\Acache\./

  def self.test_db?(config)
    return false if ENV["DATABASE_URL"].present? || config.env_name.to_s != "test"

    name = File.basename(config.database.to_s)
    name.match?(TEST_FILE) && !name.match?(REAL_FILE) && safe_location?(config.database.to_s)
  end

  # Real path (symlinks resolved) must sit under Rails.root/tmp, never under storage/ (even through a symlinked
  # tmp), and the file itself must not be a symlink. Test databases live in tmp/; storage/ is the real data dir.
  def self.safe_location?(database)
    path = File.expand_path(database, Rails.root)
    return false if File.symlink?(path)

    real = File.exist?(path) ? File.realpath(path) : File.join(File.realpath(File.dirname(path)), File.basename(path))
    tmp = File.realpath(Rails.root.join("tmp")) + File::SEPARATOR
    storage = File.expand_path(Rails.root.join("storage").to_s)
    storage = File.realpath(storage) if File.exist?(storage)
    real.start_with?(tmp) && !real.start_with?(storage + File::SEPARATOR) && !tmp.start_with?(storage + File::SEPARATOR)
  rescue SystemCallError
    false
  end

  # target: a db_config, or an env name (checks every config of that env).
  def self.test_env?(target)
    configs = target.respond_to?(:env_name) ? [ target ] : ActiveRecord::Base.configurations.configs_for(env_name: target.to_s)
    configs.any? && configs.all? { |c| test_db?(c) }
  end

  def self.deny!(action, target)
    return true if test_env?(target)

    raise Refused, "Refusing DatabaseTasks.#{action} on #{target.respond_to?(:database) ? target.database : target.inspect}: " \
                   "databases are never dropped, purged, truncated or overwritten outside the test env " \
                   "(test env + test-named file + no DATABASE_URL). No opt-in exists."
  end

  def self.empty?(db_config, tasks)
    return true if test_env?(db_config)

    tasks.send(:with_temporary_pool, db_config) do |pool|
      pool.with_connection { |c| (c.tables - %w[schema_migrations ar_internal_metadata]).empty? }
    end
  rescue ActiveRecord::NoDatabaseError
    true
  rescue StandardError
    false # unreadable (e.g. locked SQLCipher): treat as non-empty
  end
end

# SQLiteDatabaseTasks#drop/#purge FileUtils.rm the file directly, bypassing DatabaseTasks.
module DbWipeGuard::SQLiteFiles
  def drop  = DbWipeGuard.deny!(:drop, send(:db_config)) && super
  def purge = DbWipeGuard.deny!(:purge, send(:db_config)) && super
end

ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(DbWipeGuard)
ActiveRecord::Tasks::SQLiteDatabaseTasks.prepend(DbWipeGuard::SQLiteFiles)
