namespace :db do
  desc "Encrypt configured plaintext SQLite databases with SQLCipher (run offline: stop puma and bin/jobs first)"
  task encrypt_sqlite: :environment do
    env = ENV["DB_ENV"].presence || Rails.env

    migrator = SqlcipherDatabaseMigrator.new(key_hex: RecoverySecret.sqlcipher_key_hex)

    results = migrator.migrate_configured!(env: env)
    abort "No SQLCipher-enabled SQLite databases are configured for #{env}." if results.empty?

    results.each do |result|
      case result.status
      when :encrypted
        puts "Encrypted #{result.path}"
      when :already_encrypted
        puts "Already encrypted: #{result.path}"
      when :missing
        puts "Missing, will be created encrypted by db:prepare: #{result.path}"
      end
    end
  end
end
