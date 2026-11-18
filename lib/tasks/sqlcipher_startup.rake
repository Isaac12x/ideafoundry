namespace :db do
  desc "Run db:prepare unless an encrypted SQLCipher database is waiting for the browser recovery passphrase"
  task prepare_if_unlocked: :environment do
    env = ENV["DB_ENV"].presence || Rails.env
    locked_paths = SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: env)

    if locked_paths.any?
      puts "Skipping db:prepare because encrypted SQLCipher database(s) need the recovery passphrase:"
      locked_paths.each { |path| puts "  #{path}" }
      puts "Start the web server and enter the recovery passphrase in the browser to unlock encrypted data."
      next
    end

    Rake::Task["db:prepare"].invoke

    # New auto_encrypt DBs (cable) created plaintext before a key existed: encrypt once it does.
    ActiveRecord::Base.connection_handler.connection_pool_list.each(&:disconnect!)
    encrypted = SqlcipherDatabaseMigrator.encrypt_auto!(env: env)
    encrypted.each { |path| puts "Encrypted #{path}" }
  end
end
