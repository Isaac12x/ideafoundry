require "test_helper"

class BacklogFileSyncTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @previous_path = Rails.application.config.x.backlog_backup_path
    @file = Rails.root.join("tmp", "test_backlog_sync_#{SecureRandom.hex(4)}.md")
    Rails.application.config.x.backlog_backup_path = @file.to_s
  end

  def teardown
    Rails.application.config.x.backlog_backup_path = @previous_path
    File.delete(@file) if File.exist?(@file)
  end

  test "export renders heading, id comment, checklist and links" do
    item = BuildItem.create!(user: @user, title: "Ship it", pinned: true,
                             description: "- [ ] step one",
                             links: [{ "url" => "https://x.test", "label" => "Docs" }])

    BacklogFileSync.export(@user)
    content = File.read(@file)

    assert_includes content, "## [ ] Ship it"
    assert_includes content, "<!-- id:#{item.id} pin:1 -->"
    assert_includes content, "- [ ] step one"
    assert_includes content, "Links:"
    assert_includes content, "- Docs — https://x.test"
  end

  test "import creates items from id-less blocks" do
    content = <<~MD
      # Backlog

      ## [ ] Fresh idea   <!-- pin:1 -->
      - [ ] do this
    MD

    assert_difference("@user.build_items.count", 1) do
      BacklogFileSync.new(@user).import(content)
    end

    created = @user.build_items.order(:created_at).last
    assert_equal "Fresh idea", created.title
    assert created.pinned?
    assert_includes created.description, "- [ ] do this"
  end

  test "import updates an existing item by id" do
    item = BuildItem.create!(user: @user, title: "Old title", description: "old")
    content = <<~MD
      # Backlog

      ## [ ] New title   <!-- id:#{item.id} -->
      new body
    MD

    BacklogFileSync.new(@user).import(content)

    item.reload
    assert_equal "New title", item.title
    assert_equal "new body", item.description
  end

  test "import archives items missing from the file" do
    keep = BuildItem.create!(user: @user, title: "Keep")
    drop = BuildItem.create!(user: @user, title: "Drop")

    content = "# Backlog\n\n## [ ] Keep   <!-- id:#{keep.id} -->\n"
    BacklogFileSync.new(@user).import(content)

    assert_not keep.reload.completed
    assert drop.reload.completed, "missing item should be soft-deleted (archived)"
  end

  test "import coerces completion to pending when checklist is incomplete" do
    item = BuildItem.create!(user: @user, title: "Has subs")
    content = "# Backlog\n\n## [x] Has subs   <!-- id:#{item.id} -->\n- [ ] not done\n"

    BacklogFileSync.new(@user).import(content)
    assert_not item.reload.completed
  end

  test "sync_from_file round-trips without spurious changes" do
    BuildItem.create!(user: @user, title: "Stable", description: "- [ ] keep me")
    BacklogFileSync.export(@user)

    assert_no_difference("@user.build_items.count") do
      BacklogFileSync.sync_from_file(@user)
    end
    # File equals the canonical render => no further import/export churn.
    assert_equal BacklogFileSync.new(@user).render, File.read(@file)
  end
end
