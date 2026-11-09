require "test_helper"

class ListItemsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.order(:id).first
    @list = @user.lists.create!(name: "Anything", kind: :named)
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "list-items-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "research", "Gummies"))
    File.write(File.join(@kb_dir, "research", "Gummies", ".kb-project.yml"), "id: x\ngoal: find out\nstatus: active\nprivate: true\n")
    File.write(File.join(@kb_dir, "research", "notes.md"), "hi")
    @user.update_kb_folders([ @kb_dir ])
    @src = KbSource.list(@user).index { |s| File.expand_path(s[:path]) == File.expand_path(@kb_dir) }
    assert_not_nil @src
  end

  def teardown
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "adds free text, a link, and a KB entry to a named list" do
    post list_items_path(@list), params: { text: "Call the supplier" }
    post list_items_path(@list), params: { text: "https://example.com/a" }
    post list_items_path(@list), params: { pick: "kb:#{@src}:project:research/Gummies" }

    post list_items_path(@list), params: { text: "Supplier site https://x.com/a" }

    assert_redirected_to list_path(@list)
    note, link, kb, titled = @list.list_items.to_a
    assert_equal [ "Supplier site", "https://x.com/a" ], [ titled.title, titled.url ]
    assert_equal [ "Call the supplier", nil ], [ note.title, note.url ]
    assert_equal "https://example.com/a", link.url
    assert_equal "Gummies", kb.title
    assert_equal kb_path(src: @src, project: "research/Gummies"), kb.url
    assert_equal [ 1, 2, 3, 4 ], [ note, link, kb, titled ].map(&:position)

    get list_path(@list)
    assert_select ".named-list-item", text: /Call the supplier/
    assert_select "a[href=?][target=_blank]", "https://example.com/a"
  end

  test "picks an idea onto a named list and shows a single add box" do
    idea = @user.ideas.create!(title: "Pickable", state: :idea_new)
    post list_items_path(@list), params: { pick: "idea:#{idea.id}" }
    assert_equal "Idea added to the list.", flash[:notice]
    assert_includes @list.ideas.reload, idea

    get list_path(@list)
    assert_select "form.list-anything", 1
    assert_select "[data-controller=idea-search]", 0
  end

  test "idea picks outside the user's kept non-draft ideas 404 and add nothing" do
    other = User.create!(email: "pick-other@example.com", name: "Other").ideas.create!(title: "Theirs")
    draft = @user.ideas.create!(title: "Draft", draft: true)
    gone = @user.ideas.create!(title: "Gone", discarded_at: Time.current)
    [ other.id, draft.id, gone.id, "abc", "" ].each do |id|
      assert_no_difference -> { IdeaList.count } do
        post list_items_path(@list), params: { pick: "idea:#{id}" }
      end
      assert_response :not_found
    end
  end

  test "bad KB picks are refused and add nothing" do
    [ "kb:#{@src}", "kb:#{@src}:file:", "kb:#{@src}:file:../x", "kb:#{@src}:file:research/missing", "kb:-1:file:research/notes.md", "kb:99:file:a" ].each do |pick|
      assert_no_difference -> { ListItem.count } do
        post list_items_path(@list), params: { pick: pick }
      end
      assert_equal "That knowledge base entry no longer exists.", flash[:alert], pick
    end
  end

  test "KB file type comes from disk, not the pick" do
    post list_items_path(@list), params: { pick: "kb:#{@src}:project:research/notes.md" }
    assert_equal kb_path(src: @src, file: "research/notes.md"), @list.list_items.last.url
  end

  test "picking the same idea twice keeps one row" do
    idea = @user.ideas.create!(title: "Twice", state: :idea_new)
    2.times { post list_items_path(@list), params: { pick: "idea:#{idea.id}" } }
    assert_equal 1, @list.idea_lists.where(idea: idea).count
  end

  test "plain text has no url and long text is capped for validation" do
    assert_nil ListItem.from_text("plain words").url
    assert_not ListItem.from_text("x" * 5000).valid?
  end

  test "edit page lists ideas and items for a named list" do
    idea = @user.ideas.create!(title: "On edit", state: :idea_new)
    @list.idea_lists.create!(idea: idea)
    @list.list_items.create!(title: "An item")
    get edit_list_path(@list)
    assert_select ".named-list-item", text: /On edit/
    assert_select ".named-list-item", text: /An item/
  end

  test "rejects unsafe urls and kanban lists" do
    assert_not ListItem.new(list: @list, title: "x", url: "javascript:alert(1)").valid?
    assert_not ListItem.new(list: @list, title: "x", url: "//evil.example").valid?
    assert_not ListItem.new(list: @list, title: "x", url: "/\\evil.com").valid?

    kanban = @user.lists.kanban.first || @user.lists.create!(name: "Backlog")
    post list_items_path(kanban), params: { text: "nope" }
    assert_response :not_found
  end

  test "host is the external link host only" do
    assert_equal "example.com", ListItem.new(title: "x", url: "https://example.com/a").host
    assert_nil ListItem.new(title: "x", url: "/kb?src=0").host
    assert_nil ListItem.new(title: "x").host
  end

  test "removes an item" do
    item = @list.list_items.create!(title: "Gone soon")
    delete list_item_path(@list, item)
    assert_redirected_to list_path(@list)
    assert_not ListItem.exists?(item.id)
  end

  test "blank text is refused with a message" do
    post list_items_path(@list), params: { text: " " }
    assert_equal "Type something to add.", flash[:alert]
    assert_equal 0, @list.list_items.count
  end

  test "cannot remove an item from another user's list" do
    other = User.create!(email: "other-list@example.com", name: "Other").lists.create!(name: "Theirs", kind: :named)
    item = other.list_items.create!(title: "Theirs")
    delete list_item_path(other, item)
    assert_response :not_found
    assert ListItem.exists?(item.id)
  end

  test "index counts items on a named list card" do
    @list.list_items.create!(title: "One")
    @list.list_items.create!(title: "Two")
    get lists_path
    assert_select "p", text: /· 2 items/
  end

  test "new list form labels the board picker and offers the kanban option" do
    get new_list_path(kind: "named")
    assert_select ".list-new-form .list-new-board label", text: "Board"
    assert_select "option[value=kanban]", text: "Column on a kanban board"
    assert_select ".list-new-form .form-text", text: /A kanban column sits on a board/
  end
end
