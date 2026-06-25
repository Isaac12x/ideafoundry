require "test_helper"

class BuildItemsControllerTest < ActionDispatch::IntegrationTest
  def setup
    # ApplicationController#set_user uses User.first, which returns the user
    # with the lowest primary key. With fixtures, that's users(:two).
    @user = User.first
    @previous_backlog_enabled = Rails.application.config.x.backlog_enabled
    Rails.application.config.x.backlog_enabled = true

    # Isolate the backup file so sync never touches the real storage/backlog.md.
    @previous_backup_path = Rails.application.config.x.backlog_backup_path
    @backup_file = Rails.root.join("tmp", "test_backlog_#{SecureRandom.hex(4)}.md")
    Rails.application.config.x.backlog_backup_path = @backup_file.to_s
  end

  def teardown
    Rails.application.config.x.backlog_enabled = @previous_backlog_enabled
    Rails.application.config.x.backlog_backup_path = @previous_backup_path
    File.delete(@backup_file) if File.exist?(@backup_file)
  end

  test "GET index" do
    BuildItem.create!(user: @user, title: "Item 1")
    get build_items_path
    assert_response :success
    assert_select ".backlog-item", 1
  end

  test "POST create with valid params" do
    assert_difference("BuildItem.count", 1) do
      post build_items_path, params: { build_item: { title: "New item" } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "POST create attaches uploaded images" do
    assert_difference("BuildItem.count", 1) do
      post build_items_path,
           params: { build_item: { title: "New item", images: [uploaded_image("mockup.png")] } },
           as: :turbo_stream
    end

    item = BuildItem.order(:created_at).last
    assert_response :success
    assert_equal 1, item.images.count
    assert_equal "mockup.png", item.images.first.filename.to_s
    assert_includes @response.body, "backlog-image-thumb"
  end

  test "POST create with blank title" do
    assert_no_difference("BuildItem.count") do
      post build_items_path, params: { build_item: { title: "" } }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "PATCH update" do
    item = BuildItem.create!(user: @user, title: "Old")
    patch build_item_path(item), params: { build_item: { title: "New" } }, as: :turbo_stream
    assert_response :success
    assert_equal "New", item.reload.title
  end

  test "PATCH update appends uploaded images" do
    item = BuildItem.create!(user: @user, title: "With images")
    item.images.attach(io: StringIO.new("\x89PNG\r\n\x1a\n"), filename: "existing.png", content_type: "image/png")

    patch build_item_path(item),
          params: { build_item: { images: [uploaded_image("wireframe.png")] } },
          as: :turbo_stream

    assert_response :success
    assert_equal 2, item.reload.images.count
    assert_equal ["existing.png", "wireframe.png"], item.images.map { |image| image.filename.to_s }
    assert_includes @response.body, "backlog-image-thumb"
  end

  test "PATCH update keeps the rendered item at its current backlog index" do
    BuildItem.create!(user: @user, title: "First", position: 1)
    item = BuildItem.create!(user: @user, title: "Second", position: 2)

    patch build_item_path(item), params: { build_item: { title: "Updated second" } }, as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "backlog-index"
    assert_includes @response.body, ">2</span>"
  end

  test "GET cancel edit replaces the edit form with the same backlog item" do
    item = BuildItem.create!(user: @user, title: "Cancel me")

    get cancel_edit_build_item_path(item), as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "build_item_#{item.id}"
    assert_includes @response.body, "Cancel me"
  end

  test "DELETE destroy" do
    item = BuildItem.create!(user: @user, title: "Delete me")
    assert_difference("BuildItem.count", -1) do
      delete build_item_path(item), as: :turbo_stream
    end
    assert_response :success
  end

  test "DELETE destroy refreshes counters and empty state" do
    item = BuildItem.create!(user: @user, title: "Only item")

    delete build_item_path(item), as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "backlog_queued_count"
    assert_includes @response.body, ">0</span>"
    assert_includes @response.body, "build_items_empty"
  end

  test "PATCH toggle marks complete" do
    item = BuildItem.create!(user: @user, title: "Toggle me")
    patch toggle_build_item_path(item), as: :turbo_stream
    assert_response :success
    assert item.reload.completed
  end

  test "PATCH toggle marks pending" do
    item = BuildItem.create!(user: @user, title: "Toggle me", completed: true, completed_at: Time.current)
    patch toggle_build_item_path(item), as: :turbo_stream
    assert_response :success
    assert_not item.reload.completed
  end

  test "PATCH toggle does not mark complete while checklist items remain" do
    item = BuildItem.create!(user: @user, title: "Toggle me", description: "- [ ] Subtask")

    patch toggle_build_item_path(item), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_not item.reload.completed
  end

  test "PATCH toggle checklist item flips a checklist line" do
    item = BuildItem.create!(user: @user, title: "Grouped", description: "- [ ] Subtask")

    patch toggle_checklist_item_build_item_path(item, line: 0), as: :turbo_stream

    assert_response :success
    assert_includes item.reload.description, "- [x] Subtask"
    assert_includes @response.body, "(0/1)"
  end

  test "PATCH reorder updates positions" do
    i1 = BuildItem.create!(user: @user, title: "A", position: 1)
    i2 = BuildItem.create!(user: @user, title: "B", position: 2)
    i3 = BuildItem.create!(user: @user, title: "C", position: 3)
    patch reorder_build_items_path, params: { order: [i3.id, i1.id, i2.id] }, as: :turbo_stream
    assert_response :success
    assert_equal 1, i3.reload.position
    assert_equal 2, i1.reload.position
    assert_equal 3, i2.reload.position
  end

  test "PATCH pin toggles pinned and floats item to top of pending list" do
    a = BuildItem.create!(user: @user, title: "Alpha", position: 1)
    b = BuildItem.create!(user: @user, title: "Bravo", position: 2)

    patch pin_build_item_path(b), as: :turbo_stream

    assert_response :success
    assert b.reload.pinned?
    # Pinned item now sorts ahead of the unpinned one.
    assert_equal [b.id, a.id], @user.build_items.pending.pluck(:id)
  end

  test "PATCH pin again unpins" do
    item = BuildItem.create!(user: @user, title: "Alpha", pinned: true)
    patch pin_build_item_path(item), as: :turbo_stream
    assert_response :success
    assert_not item.reload.pinned?
  end

  test "PATCH join folds source into target as a checklist subitem" do
    target = BuildItem.create!(user: @user, title: "Parent", position: 1)
    source = BuildItem.create!(user: @user, title: "Child", position: 2, description: "- [ ] nested")

    assert_difference("BuildItem.count", -1) do
      patch join_build_items_path, params: { source_id: source.id, target_id: target.id }, as: :turbo_stream
    end

    assert_response :success
    assert_not BuildItem.exists?(source.id)
    assert_includes target.reload.description, "- [ ] Child"
    assert_includes target.description, "nested"
  end

  test "PATCH join rejects joining completed items" do
    target = BuildItem.create!(user: @user, title: "Parent")
    source = BuildItem.create!(user: @user, title: "Done", completed: true, completed_at: Time.current)

    assert_no_difference("BuildItem.count") do
      patch join_build_items_path, params: { source_id: source.id, target_id: target.id }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "stats counts include checklist subitems" do
    BuildItem.create!(user: @user, title: "Has subs", description: "- [ ] one\n- [x] two")

    get build_items_path

    assert_response :success
    # 1 pending item + 1 unchecked subitem = 2 queued; 1 checked subitem = 1 done.
    assert_select "#backlog_queued_count", text: "2"
    assert_select "#backlog_done_count", text: "1"
  end

  test "mutations export the backlog to the backup file" do
    post build_items_path, params: { build_item: { title: "Backed up" } }, as: :turbo_stream
    assert File.exist?(@backup_file)
    assert_includes File.read(@backup_file), "Backed up"
  end

  test "GET index redirects when backlog is disabled" do
    Rails.application.config.x.backlog_enabled = false

    get build_items_path

    assert_redirected_to root_path
    assert_equal "Backlog is not enabled.", flash[:alert]
  end

  private

  def uploaded_image(filename)
    file = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    file.binmode
    file.write("\x89PNG\r\n\x1a\n")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: filename)
  end
end
