require "test_helper"

class BacklogLockEscapeTest < ActionDispatch::IntegrationTest
  def setup
    reset!
    User.find_each { |user| user.update!(settings: { "typing_lock" => { "enabled" => true } }) }
    @user = User.first

    @previous_backlog_enabled = Rails.application.config.x.backlog_enabled
    Rails.application.config.x.backlog_enabled = true

    @previous_backup_path = Rails.application.config.x.backlog_backup_path
    @backup_file = Rails.root.join("tmp", "test_backlog_#{SecureRandom.hex(4)}.md")
    Rails.application.config.x.backlog_backup_path = @backup_file.to_s
  end

  def teardown
    Rails.application.config.x.backlog_enabled = @previous_backlog_enabled
    Rails.application.config.x.backlog_backup_path = @previous_backup_path
    File.delete(@backup_file) if File.exist?(@backup_file)
  end

  test "backlog opens while the workspace is locked" do
    get build_items_path

    assert_response :success
    assert_select ".backlog-only-strip"
    assert_select ".backlog-only-strip__unlock[href=?]", root_path
  end

  test "capturing a backlog item while locked works" do
    assert_difference("BuildItem.count", 1) do
      post build_items_path, params: { build_item: { title: "Passing thought" } }, as: :turbo_stream
    end

    assert_response :success
  end

  test "lock screen offers the backlog side-door" do
    get root_path
    follow_redirect!

    assert_response :success
    assert_select "a.lock-sidedoor[href=?]", build_items_path
  end

  test "side-door is hidden when the backlog is disabled" do
    Rails.application.config.x.backlog_enabled = false

    get root_path
    follow_redirect!
    assert_select "a.lock-sidedoor", count: 0

    get build_items_path
    assert_redirected_to enroll_typing_lock_path(return_to: build_items_path)
  end

  # The packaged app runs in production locally (bin/start defaults RAILS_ENV=production),
  # so the escape hatch has to survive it — BACKLOG_ENABLED is the opt-in, not Rails.env.
  test "side-door stays available in production" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      get root_path
      follow_redirect!
      assert_select "a.lock-sidedoor[href=?]", build_items_path

      get build_items_path
      assert_response :success
    end
  end

  test "backlog access does not unlock the rest of the workspace" do
    get build_items_path
    assert_response :success

    get ideas_path
    assert_response :redirect
  end

  test "backlog page keeps lock-sensitive chrome out" do
    get build_items_path

    assert_select "body[data-typing-activity-url-value]", count: 0
    assert_select ".command-palette", count: 0
    assert_select ".app-notes-bar", count: 0
  end
end
