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

  private

  def resolve_name(*arguments, env: {})
    Open3.capture3(
      env,
      "/bin/zsh",
      "-c",
      'source "$1"; shift; idea_app_installation_name "$@"',
      "idea-app-installation-test",
      HELPER,
      *arguments
    )
  end
end
