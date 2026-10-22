require "test_helper"

# The OS sandbox cannot be exercised from a test suite; this pins the committed configuration instead.
class ClaudeSandboxSettingsTest < ActiveSupport::TestCase
  PROJECT = JSON.parse(File.read(Rails.root.join(".claude/settings.json")))
  MANAGED = JSON.parse(File.read(Rails.root.join("docs/claude-managed-settings.json")))
  MAIN_CHECKOUT = "/Users/iamin/work/projects/active/ideafoundry/repos/idea-app".freeze
  GUARDS = %w[config/initializers/db_wipe_guard.rb lib/tasks/db_guard.rake config/database.yml].freeze

  test "project settings enable a fail-closed sandbox with no unsandboxed escape hatch" do
    sandbox = PROJECT.fetch("sandbox")
    assert_equal true, sandbox["enabled"]
    assert_equal true, sandbox["failIfUnavailable"]
    assert_equal false, sandbox["allowUnsandboxedCommands"]
  end

  test "project settings deny sandboxed writes to storage and the guards (project-relative ./ paths)" do
    deny = PROJECT.dig("sandbox", "filesystem", "denyWrite")
    [ "./storage", "./storage/recovery_passphrase.key", "./.claude/hooks", "./.claude/hooks/guard_db.sh", *GUARDS.map { |g| "./#{g}" } ].each do |path|
      assert_includes deny, path
    end
  end

  test "project settings deny Edit on storage and the guards (/ is project-relative in permission rules)" do
    deny = PROJECT.dig("permissions", "deny")
    [ "Edit(/storage/**)", "Edit(/.claude/hooks/**)", *GUARDS.map { |g| "Edit(/#{g})" } ].each { |rule| assert_includes deny, rule }
  end

  test "project settings keep the DB guard hooks and let bundle, yarn, git and gh reach their hosts" do
    commands = PROJECT.dig("hooks", "PreToolUse").flat_map { |g| g["hooks"] }.map { |h| h["command"] }
    assert commands.any? { |c| c.include?("guard_db.sh") && !c.include?("--file") }
    assert commands.any? { |c| c.include?("guard_db.sh --file") }
    domains = PROJECT.dig("sandbox", "network", "allowedDomains")
    %w[github.com api.github.com rubygems.org registry.npmjs.org registry.yarnpkg.com].each { |host| assert_includes domains, host }
    assert_includes PROJECT.dig("sandbox", "excludedCommands"), "git push *"
  end

  test "managed template uses absolute paths for the main checkout and does not lock out the owner's own rules" do
    sandbox = MANAGED.fetch("sandbox")
    assert_equal true, sandbox["enabled"]
    assert_equal true, sandbox["failIfUnavailable"]
    assert_equal false, sandbox["allowUnsandboxedCommands"]

    deny = sandbox.dig("filesystem", "denyWrite")
    [ "storage", "storage/recovery_passphrase.key", ".claude/hooks", ".claude/hooks/guard_db.sh", *GUARDS ].each do |path|
      assert_includes deny, "#{MAIN_CHECKOUT}/#{path}"
    end

    rules = MANAGED.dig("permissions", "deny")
    [ "storage/**", ".claude/hooks/**", *GUARDS ].each { |path| assert_includes rules, "Edit(/#{MAIN_CHECKOUT}/#{path})" }

    assert_not MANAGED.key?("allowManagedPermissionRulesOnly")
    assert_not MANAGED.key?("allowManagedHooksOnly")
    assert_not MANAGED.dig("permissions")&.key?("allowManagedPermissionRulesOnly")
  end
end
