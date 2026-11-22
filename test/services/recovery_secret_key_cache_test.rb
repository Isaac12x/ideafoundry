require "test_helper"

class RecoverySecretKeyCacheTest < ActiveSupport::TestCase
  setup { RecoverySecret.clear_key_cache! }
  teardown { RecoverySecret.clear_key_cache! }

  def counting_scrypt
    calls = 0
    real = OpenSSL::KDF.method(:scrypt)
    [ ->(*args, **kw) { calls += 1; real.call(*args, **kw) }, -> { calls } ]
  end

  test "a derived key is computed once per passphrase and cost" do
    scrypt, calls = counting_scrypt

    OpenSSL::KDF.stub(:scrypt, scrypt) do
      first = RecoverySecret.sqlcipher_key_hex_for("pw", n: RecoverySecret::SCRYPT_N)
      assert_equal first, RecoverySecret.sqlcipher_key_hex_for("pw", n: RecoverySecret::SCRYPT_N)
      assert_equal 1, calls.call

      RecoverySecret.sqlcipher_key_hex_for("pw", n: RecoverySecret::SCRYPT_N_DEFAULT)
      RecoverySecret.sqlcipher_key_hex_for("other", n: RecoverySecret::SCRYPT_N)
      assert_equal 3, calls.call, "another cost or another passphrase is a different key"
    end
  end

  test "the cache is cleared when the passphrase changes, and on lock" do
    original = ENV[RecoverySecret::PASSPHRASE_FILE_ENV]
    dir = Rails.root.join("tmp/key_cache_test_#{SecureRandom.hex(6)}")
    ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = dir.join("recovery_passphrase.key").to_s # never the real credential file
    scrypt, calls = counting_scrypt
    OpenSSL::KDF.stub(:scrypt, scrypt) do
      RecoverySecret.sqlcipher_key_hex_for("pw", n: RecoverySecret::SCRYPT_N)
      RecoverySecret.send(:store_credential!, "pw", kdf_n: RecoverySecret::SCRYPT_N)
      RecoverySecret.sqlcipher_key_hex_for("pw", n: RecoverySecret::SCRYPT_N)
      assert_equal 2, calls.call, "storing a credential clears the cache"

      RecoverySecret.clear_key_cache!
      RecoverySecret.sqlcipher_key_hex_for("pw", n: RecoverySecret::SCRYPT_N)
      assert_equal 3, calls.call, "locking clears the cache"
    end
  ensure
    original.nil? ? ENV.delete(RecoverySecret::PASSPHRASE_FILE_ENV) : ENV[RecoverySecret::PASSPHRASE_FILE_ENV] = original
    FileUtils.rm_rf(dir) if dir&.exist?
  end

  test "a foreign generation change clears derived keys before reconnecting" do
    original_generation_path = RecoverySecret.method(:generation_path)
    original_connection_generation = RecoverySecret.instance_variable_get(:@connection_generation)
    original_cache_generation = RecoverySecret.instance_variable_get(:@cache_generation)
    path = Rails.root.join("tmp/key_cache_generation_test_#{SecureRandom.hex(6)}")
    RecoverySecret.define_singleton_method(:generation_path) { path }
    RecoverySecret.bump_generation!
    RecoverySecret.sqlcipher_key_hex_for("pw", n: RecoverySecret::SCRYPT_N)
    assert_equal 1, RecoverySecret.instance_variable_get(:@key_cache).size

    File.write(path, SecureRandom.hex(8)) # another worker changed or cleared the passphrase
    ActiveRecord::Base.connection_handler.stub(:connection_pool_list, []) do
      assert RecoverySecret.reset_connections_if_changed!
    end

    assert_empty RecoverySecret.instance_variable_get(:@key_cache)
  ensure
    RecoverySecret.define_singleton_method(:generation_path, original_generation_path) if original_generation_path
    RecoverySecret.instance_variable_set(:@connection_generation, original_connection_generation)
    RecoverySecret.instance_variable_set(:@cache_generation, original_cache_generation)
    RecoverySecret.clear_key_cache!
    FileUtils.rm_f(path) if path
  end

  test "the cache lives in process memory only and never keeps the raw passphrase" do
    RecoverySecret.sqlcipher_key_hex_for("super secret passphrase", n: RecoverySecret::SCRYPT_N)
    cache = RecoverySecret.instance_variable_get(:@key_cache)

    assert_equal 1, cache.size
    assert_not_includes cache.keys.flatten.map(&:to_s).join, "super secret passphrase"
  end

  test "the cache is bounded" do
    (RecoverySecret::KEY_CACHE_LIMIT + 5).times { |i| RecoverySecret.sqlcipher_key_hex_for("pw#{i}", n: RecoverySecret::SCRYPT_N) }

    assert_operator RecoverySecret.instance_variable_get(:@key_cache).size, :<=, RecoverySecret::KEY_CACHE_LIMIT
  end
end
