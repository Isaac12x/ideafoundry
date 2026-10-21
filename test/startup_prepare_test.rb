require "test_helper"
require "open3"
require "tmpdir"

# Every way of starting the app must install JS deps, build JS (incl. Excalidraw), migrate and
# precompile with no manual step. Dev goes through bin/prepare; production-style launchers go
# through assets:precompile (jsbundling runs yarn install + yarn build) + db:prepare_if_unlocked.
class StartupPrepareTest < ActiveSupport::TestCase
  ROOT = Rails.root

  test "SKIP_PREPARE=1 bin/prepare exits 0 and does nothing" do
    out, status = Open3.capture2e({ "SKIP_PREPARE" => "1" }, ROOT.join("bin/prepare").to_s)
    assert status.success?
    assert_empty out
  end

  test "bin/dev runs bin/prepare before foreman and stops if it fails" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "bin"))
      FileUtils.cp(ROOT.join("bin/dev"), File.join(dir, "bin/dev"))
      File.write(File.join(dir, "bin/find_available_port"), "#!/bin/sh\necho \"$1\"\n")
      File.write(File.join(dir, "bin/prepare"), "#!/bin/sh\necho prepare >> calls\nexit ${PREPARE_RC:-0}\n")
      File.write(File.join(dir, "foreman"), "#!/bin/sh\necho foreman >> calls\n")
      File.write(File.join(dir, "gem"), "#!/bin/sh\nexit 0\n") # `gem list foreman -i` => installed
      Dir[File.join(dir, "{bin/*,foreman,gem}")].each { |f| FileUtils.chmod(0o755, f) }
      env = { "PATH" => "#{dir}:#{ENV['PATH']}" }

      _, status = Open3.capture2e(env, "bin/dev", chdir: dir)
      assert status.success?
      assert_equal %w[prepare foreman], File.read(File.join(dir, "calls")).split

      File.delete(File.join(dir, "calls"))
      _, status = Open3.capture2e(env.merge("PREPARE_RC" => "1"), "bin/dev", chdir: dir)
      assert_not status.success?
      assert_equal %w[prepare], File.read(File.join(dir, "calls")).split
    end
  end

  # Structural guard: these launchers get JS install + build through the jsbundling hook on precompile.
  test "production launchers migrate and precompile" do
    assert Gem.loaded_specs.key?("jsbundling-rails")
    %w[bin/start bin/start_idea_app.sh bin/install].each do |file|
      src = ROOT.join(file).read
      assert_includes src, "db:prepare_if_unlocked", file
      assert_includes src, "assets:precompile", file
    end
  end
end
