require "test_helper"
require "open3"

class IdeaAppInstallationTest < ActiveSupport::TestCase
  HELPER = Rails.root.join("bin/idea_app_installation").to_s

  test "defaults to the legacy idea-app installation name" do
    stdout, stderr, status = resolve_name

    assert status.success?, stderr
    assert_equal "idea-app\n", stdout
  end

  test "accepts a positional installation name" do
    stdout, stderr, status = resolve_name("research-vault")

    assert status.success?, stderr
    assert_equal "research-vault\n", stdout
  end

  test "uses the environment name when no positional name is given" do
    stdout, stderr, status = resolve_name(env: { "IDEA_APP_INSTALLATION_NAME" => "private_vault" })

    assert status.success?, stderr
    assert_equal "private_vault\n", stdout
  end

  test "positional name takes precedence over the environment" do
    stdout, stderr, status = resolve_name("research", env: { "IDEA_APP_INSTALLATION_NAME" => "personal" })

    assert status.success?, stderr
    assert_equal "research\n", stdout
  end

  test "rejects names that Docker Compose cannot use" do
    _stdout, stderr, status = resolve_name("Research Vault")

    assert_equal 64, status.exitstatus
    assert_includes stderr, "Invalid installation name: Research Vault"
  end

  test "rejects extra arguments" do
    _stdout, stderr, status = resolve_name("research", "extra")

    assert_equal 64, status.exitstatus
    assert_includes stderr, "Usage:"
  end

  test "rejects an explicitly empty installation name" do
    _stdout, stderr, status = resolve_name("")

    assert_equal 64, status.exitstatus
    assert_includes stderr, "Installation name cannot be empty"
  end

  test "limits installation names to 63 characters" do
    accepted_name = "a" * 63
    stdout, stderr, status = resolve_name(accepted_name)

    assert status.success?, stderr
    assert_equal "#{accepted_name}\n", stdout

    _stdout, stderr, status = resolve_name("a" * 64)
    assert_equal 64, status.exitstatus
    assert_includes stderr, "at most 63 characters"
  end

  test "preserves legacy ports and system Caddy behavior for idea-app" do
    assert_equal "3333\n", run_helper("idea_app_default_port", "idea-app", "app").first
    assert_equal "8000\n", run_helper("idea_app_default_port", "idea-app", "voice_id").first
    assert_equal "8001\n", run_helper("idea_app_default_port", "idea-app", "ocr").first
    assert_equal "8443\n", run_helper("idea_app_default_port", "idea-app", "https").first
    assert_equal "1\n", run_helper("idea_app_default_skip_caddy", "idea-app").first
  end

  test "derives stable non-overlapping ports for a named installation" do
    ports = %w[app voice_id ocr https caddy_http caddy_admin].map do |service|
      stdout, stderr, status = run_helper("idea_app_default_port", "idea-test", service)
      assert status.success?, stderr
      Integer(stdout)
    end

    assert_equal ports, ports.uniq
    assert_includes 10_000...18_000, ports[0]
    assert_includes 18_000...26_000, ports[1]
    assert_includes 26_000...34_000, ports[2]
    assert_includes 34_000...42_000, ports[3]
    assert_includes 42_000...50_000, ports[4]
    assert_includes 50_000...58_000, ports[5]
    assert_equal "0\n", run_helper("idea_app_default_skip_caddy", "idea-test").first
  end

  test "installer passes its generated secret to production setup commands" do
    installer = Rails.root.join("bin/install").read

    assert_includes installer, 'SECRET_KEY_BASE="$SECRET_KEY_BASE" RAILS_ENV=production bin/rails db:prepare_if_unlocked'
    assert_includes installer, 'SECRET_KEY_BASE="$SECRET_KEY_BASE" RAILS_ENV=production bin/rails assets:precompile'
  end

  test "identifies macOS folders that LaunchAgents cannot read" do
    %w[Desktop Documents Downloads].each do |folder|
      _stdout, _stderr, status = run_helper("idea_app_launchd_protected_path", "/Users/test/#{folder}/ideafoundry", "/Users/test")
      assert status.success?, "expected #{folder} to be protected"
    end

    _stdout, _stderr, status = run_helper("idea_app_launchd_protected_path", "/Users/test/Applications/IdeaFoundry/idea-test", "/Users/test")
    refute status.success?
  end

  private

  def resolve_name(*arguments, env: {})
    run_helper("idea_app_installation_name", *arguments, env: env)
  end

  def run_helper(function_name, *arguments, env: {})
    Open3.capture3(
      env,
      "/bin/zsh",
      "-c",
      'function_name="$1"; helper="$2"; shift 2; source "$helper"; "$function_name" "$@"',
      "idea-app-installation-test",
      function_name,
      HELPER,
      *arguments
    )
  end
end
