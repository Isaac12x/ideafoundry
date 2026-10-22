require "test_helper"

class RecoverySecretsControllerTest < ActionDispatch::IntegrationTest
  # Records connection resets when a test sets events.
  module ResetEvents
    private

    def reset_recovery_secret_database_connections!
      RecoverySecretsControllerTest.events&.push(:disconnect)
      super
    end
  end
  RecoverySecretsController.prepend(ResetEvents)

  class << self
    attr_accessor :events
  end

  setup do
    @original_recovery_passphrase_file = ENV[RecoverySecret::PASSPHRASE_FILE_ENV]
    @original_recovery_passphrase = ENV[RecoverySecret::PASSPHRASE_ENV]
    @recovery_secret_root = Rails.root.join("tmp/recovery_secret_controller_default_#{SecureRandom.hex(6)}")
    ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = @recovery_secret_root.join("recovery_passphrase.key").to_s
    ENV.delete(RecoverySecret::PASSPHRASE_ENV)
  end

  teardown do
    if @original_recovery_passphrase_file.nil?
      ENV.delete(RecoverySecret::PASSPHRASE_FILE_ENV)
    else
      ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = @original_recovery_passphrase_file
    end

    if @original_recovery_passphrase.nil?
      ENV.delete(RecoverySecret::PASSPHRASE_ENV)
    else
      ENV[RecoverySecret::PASSPHRASE_ENV] = @original_recovery_passphrase
    end

    FileUtils.rm_rf(@recovery_secret_root) if @recovery_secret_root
  end

  test "GET recovery secret renders passphrase form" do
    get recovery_secret_path(return_to: settings_security_path)

    assert_response :success
    assert_select "form[action=?][method=?]", recovery_secret_path, "post"
    assert_select "input[type=?][name=?]", "password", "recovery_passphrase"
    assert_select "input[type=?][name=?][value=?]", "hidden", "return_to", settings_security_path
    assert_select "body[data-controller]", count: 0
    assert_select ".activity-panel", count: 0
    assert_select ".nav-activity-trigger", count: 0
    assert_select ".app-dialog", count: 0
  end

  test "locked SQLCipher database asks for recovery before reading typing lock settings" do
    locked_path = Rails.root.join("tmp/encrypted_sqlcipher_before_typing.sqlite3").to_s

    SqlcipherDatabaseMigrator.stub(:locked_database_paths_without_recovery_secret, [ locked_path ]) do
      User.stub(:first, -> { raise "typing lock should not read the database before recovery unlock" }) do
        get root_path
      end
    end

    assert_redirected_to recovery_secret_path(return_to: root_path)
    assert_equal "Enter the recovery passphrase to unlock encrypted data.", flash[:alert]
  end

  test "POST recovery secret redirects to safe return path without a success notice" do
    post recovery_secret_path, params: {
      recovery_passphrase: "typed in the UI",
      return_to: settings_security_path
    }

    assert_redirected_to settings_security_path
    assert_nil flash[:notice]
  end

  test "POST recovery secret never shows success notice on the locked page" do
    user = User.first
    user.update!(settings: {
      "typing_lock" => {
        "enabled" => true,
        "fingerprint" => "configured"
      }
    })

    post recovery_secret_path, params: {
      recovery_passphrase: "typed in the UI",
      return_to: root_path
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_match(/Typing rhythm score/, response.body)
    assert_no_match(/Encrypted data unlocked\./, response.body)
    assert_select ".alert.alert-success", count: 0
  end

  test "POST recovery secret persists the verified passphrase for future app boots" do
    root = Rails.root.join("tmp/recovery_secret_controller_test_#{SecureRandom.hex(6)}")
    path = root.join("recovery_passphrase.key")

    with_recovery_passphrase_file(path) do
      post recovery_secret_path, params: {
        recovery_passphrase: "typed once on this node",
        return_to: root_path
      }

      assert_redirected_to root_path
      persisted = JSON.parse(File.read(path))
      assert_equal "typed once on this node", persisted.fetch("passphrase")
      assert_equal RecoverySecret.app_node_id, persisted.fetch("app_node_id")
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  ensure
    FileUtils.rm_rf(root) if root
  end

  test "an unlock-time rekey disconnects every pool before and after it, and writes still work afterwards" do
    events = RecoverySecretsControllerTest.events = []
    RecoverySecret.stub(:rekey_needed?, true) do
      RecoverySecret.stub(:rekey!, ->(*, **) { events << :rekey }) do
        post recovery_secret_path, params: { recovery_passphrase: "typed in the UI", return_to: root_path }
      end
    end

    assert_redirected_to root_path
    assert_equal [ :disconnect, :rekey, :disconnect ], events
    assert_nil flash[:alert]
    user = User.first
    user.update!(settings: user.settings.merge("written_after_rekey" => true))
    assert User.first.settings["written_after_rekey"]
  ensure
    RecoverySecretsControllerTest.events = nil
  end

  test "a deferred rekey does not block the unlock and tells the user" do
    [ SqlcipherDatabaseMigrator::Error.new("Database is in use by process 42. Stop the app (puma + bin/jobs) first"),
      SQLite3::BusyException.new("database is locked"), IOError.new("disk full") ].each do |error|
      RecoverySecret.stub(:rekey_needed?, true) do
        RecoverySecret.stub(:rekey!, ->(*, **) { raise error }) do
          post recovery_secret_path, params: { recovery_passphrase: "typed in the UI", return_to: root_path }
        end
      end

      assert_redirected_to root_path
      assert_match(/Unlocked, but upgrading the database key was deferred/, flash[:alert])
    end
  end

  PASSPHRASE = "typed in the UI".freeze

  def encrypted_database(name, n)
    FileUtils.mkdir_p(@recovery_secret_root)
    path = @recovery_secret_root.join(name)
    db = SQLite3::Database.new(path.to_s)
    db.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex_for(PASSPHRASE, n: n)}'"))
    db.execute("CREATE TABLE ideas (id integer primary key, title text)")
    db.execute("INSERT INTO ideas (title) VALUES ('kept')")
    db.close
    path
  end

  def opens_at_cost?(path, n)
    db = SQLite3::Database.new(path.to_s)
    db.execute(%(PRAGMA key = "x'#{RecoverySecret.sqlcipher_key_hex_for(PASSPHRASE, n: n)}'"))
    db.get_first_value("SELECT title FROM ideas") == "kept"
  rescue SQLite3::Exception
    false
  ensure
    db&.close
  end

  def stored_cost = RecoverySecret.send(:read_configured_kdf_n)

  test "with no stored credential and databases on the legacy cost, the unlock converges them and stores a matching credential" do
    legacy = encrypted_database("legacy.sqlite3", RecoverySecret::SCRYPT_N)
    assert_nil stored_cost, "nothing is stored yet"

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ legacy.to_s ]) do
      post recovery_secret_path, params: { recovery_passphrase: PASSPHRASE, return_to: root_path }
    end

    assert_redirected_to root_path
    assert_nil flash[:alert]
    assert opens_at_cost?(legacy, RecoverySecret::SCRYPT_N_DEFAULT)
    assert_equal RecoverySecret::SCRYPT_N_DEFAULT, stored_cost
    assert_equal PASSPHRASE, JSON.parse(File.read(ENV[RecoverySecret::PASSPHRASE_FILE_ENV]))["passphrase"]
    assert_not RecoverySecret.rekey_needed?
  end

  test "a fresh install with no encrypted databases stores the default cost straight away" do
    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ @recovery_secret_root.join("missing.sqlite3").to_s ]) do
      post recovery_secret_path, params: { recovery_passphrase: PASSPHRASE, return_to: root_path }
    end

    assert_equal RecoverySecret::SCRYPT_N_DEFAULT, stored_cost
  end

  test "unlock after a partial rekey (one database converted, one not) still works and converges everything" do
    converted = encrypted_database("converted.sqlite3", RecoverySecret::SCRYPT_N_DEFAULT)
    straggler = encrypted_database("straggler.sqlite3", RecoverySecret::SCRYPT_N)
    RecoverySecret.send(:store_credential!, PASSPHRASE, kdf_n: RecoverySecret::SCRYPT_N) # the credential still says "legacy"

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, [ converted.to_s, straggler.to_s ]) do
      post recovery_secret_path, params: { recovery_passphrase: PASSPHRASE, return_to: root_path }
    end

    assert_redirected_to root_path
    assert_nil flash[:alert]
    [ converted, straggler ].each { |path| assert opens_at_cost?(path, RecoverySecret::SCRYPT_N_DEFAULT), path.to_s }
    assert_not opens_at_cost?(straggler, RecoverySecret::SCRYPT_N)
    assert_equal RecoverySecret::SCRYPT_N_DEFAULT, stored_cost
  ensure
  end

  test "if storing the credential raised after every database was converted, the next unlock still works" do
    paths = [ encrypted_database("one.sqlite3", RecoverySecret::SCRYPT_N), encrypted_database("two.sqlite3", RecoverySecret::SCRYPT_N) ]
    RecoverySecret.send(:store_credential!, PASSPHRASE, kdf_n: RecoverySecret::SCRYPT_N)

    SqlcipherDatabaseMigrator.stub(:configured_database_paths, paths.map(&:to_s)) do
      RecoverySecret.stub(:store_credential!, ->(*, **) { raise IOError, "disk full" }) do
        assert_raises(IOError) { RecoverySecret.rekey!(PASSPHRASE, env: "production") }
      end
      paths.each { |path| assert opens_at_cost?(path, RecoverySecret::SCRYPT_N_DEFAULT) }
      assert_equal RecoverySecret::SCRYPT_N, stored_cost, "the credential still has the old cost"

      post recovery_secret_path, params: { recovery_passphrase: PASSPHRASE, return_to: root_path }
    end

    assert_redirected_to root_path
    assert_nil flash[:alert]
    assert_equal RecoverySecret::SCRYPT_N_DEFAULT, stored_cost
    assert_not RecoverySecret.rekey_needed?
  ensure
  end

  test "POST recovery secret rejects blank passphrase" do
    post recovery_secret_path, params: {
      recovery_passphrase: "",
      return_to: settings_security_path
    }

    assert_response :unprocessable_content
    assert_select ".recovery-secret-error", text: "Enter the recovery passphrase to continue."
  end

  private

  def with_recovery_passphrase_file(path)
    original_file = ENV[RecoverySecret::PASSPHRASE_FILE_ENV]
    original_passphrase = ENV[RecoverySecret::PASSPHRASE_ENV]
    ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = path.to_s
    ENV.delete(RecoverySecret::PASSPHRASE_ENV)

    yield
  ensure
    if original_file.nil?
      ENV.delete(RecoverySecret::PASSPHRASE_FILE_ENV)
    else
      ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = original_file
    end

    if original_passphrase.nil?
      ENV.delete(RecoverySecret::PASSPHRASE_ENV)
    else
      ENV[RecoverySecret::PASSPHRASE_ENV] = original_passphrase
    end
  end
end
