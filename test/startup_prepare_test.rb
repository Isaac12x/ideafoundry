require "test_helper"

# Every way of starting the app must install JS deps, build JS (incl. Excalidraw), migrate and
# precompile with no manual step. Dev goes through bin/prepare; production-style launchers go
# through assets:precompile (jsbundling runs yarn install + yarn build) + db:prepare_if_unlocked.
class StartupPrepareTest < ActiveSupport::TestCase
  ROOT = Rails.root

  test "bin/dev runs bin/prepare before foreman" do
    dev = ROOT.join("bin/dev").read
    assert_operator dev.index("bin/prepare"), :<, dev.index("foreman start")
  end

  test "bin/prepare installs, builds and migrates" do
    prepare = ROOT.join("bin/prepare").read
    [ "yarn install", "yarn build", "db:prepare_if_unlocked" ].each { |step| assert_includes prepare, step }
  end

  test "production launchers migrate and precompile" do
    %w[bin/start bin/start_idea_app.sh bin/install].each do |file|
      src = ROOT.join(file).read
      assert_includes src, "db:prepare_if_unlocked", file
      assert_includes src, "assets:precompile", file
    end
  end

  test "precompile is hooked to the JS build" do
    assert Gem.loaded_specs.key?("jsbundling-rails")
    assert_includes ROOT.join("package.json").read, '"build": "node esbuild.config.mjs"'
  end
end
