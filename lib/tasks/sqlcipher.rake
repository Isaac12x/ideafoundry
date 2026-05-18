namespace :db do
  desc "Encrypt configured plaintext SQLite databases with SQLCipher"
  task encrypt_sqlite: :environment do
    env = ENV["DB_ENV"].presence || Rails.env
    backup_dir = ENV["IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR"].presence || ENV["BACKUP_DIR"].presence

    migrator = SqlcipherDatabaseMigrator.new(
      key_hex: RecoverySecret.sqlcipher_key_hex,
      backup_dir: backup_dir
    )

    results = migrator.migrate_configured!(env: env)
    abort "No SQLCipher-enabled SQLite databases are configured for #{env}." if results.empty?

    results.each do |result|
      case result.status
      when :encrypted
        puts "Encrypted #{result.path}"
        puts "Plaintext backup: #{result.backup_path}"
      when :already_encrypted
        puts "Already encrypted: #{result.path}"
      when :missing
        puts "Missing, will be created encrypted by db:prepare: #{result.path}"
      end
    end
  end
end
