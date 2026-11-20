require "test_helper"

class ServiceSettingsTest < ActiveSupport::TestCase
  KEY = "SEMANTIC_SERVICE_URL".freeze

  setup { @orig = ENV.delete(KEY) }
  teardown { ENV[KEY] = @orig if @orig }

  test "precedence: settings, env, default, unset" do
    assert_nil ServiceSettings.fetch(KEY)
    assert_equal "unset", ServiceSettings.source(KEY)
    assert_equal "d", ServiceSettings.fetch(KEY, "d")

    ENV[KEY] = "http://env"
    assert_equal "http://env", ServiceSettings.fetch(KEY)
    assert_equal "env", ServiceSettings.source(KEY)

    ServiceSetting.create!(key: KEY, value: "http://db")
    assert_equal "http://db", ServiceSettings.fetch(KEY)
    assert_equal "settings", ServiceSettings.source(KEY)

    ServiceSetting.find_by(key: KEY).update!(value: " ")
    assert_equal "http://env", ServiceSettings.fetch(KEY)
    assert SemanticSearch.enabled?
  ensure
    ENV.delete(KEY)
  end

  test "db errors fall back to env" do
    ENV[KEY] = "http://env"
    ServiceSetting.stub(:where, ->(*) { raise ActiveRecord::StatementInvalid, "no table" }) do
      assert_equal "http://env", ServiceSettings.fetch(KEY)
    end
  ensure
    ENV.delete(KEY)
  end
end
