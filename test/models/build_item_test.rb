require "test_helper"

class BuildItemTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "valid with title and user" do
    item = BuildItem.new(user: @user, title: "Add dark mode")
    assert item.valid?
  end

  test "allows image attachments" do
    item = BuildItem.new(user: @user, title: "Add annotated screenshot")
    item.images.attach(io: StringIO.new("\x89PNG\r\n\x1a\n"), filename: "screenshot.png", content_type: "image/png")

    assert item.valid?
  end

  test "rejects non-image attachments" do
    item = BuildItem.new(user: @user, title: "Add annotated screenshot")
    item.images.attach(io: StringIO.new("notes"), filename: "notes.txt", content_type: "text/plain")

    assert_not item.valid?
    assert_includes item.errors[:images], "must be image files"
  end

  test "invalid without title" do
    item = BuildItem.new(user: @user, title: nil)
    assert_not item.valid?
  end

  test "invalid without user" do
    item = BuildItem.new(title: "Something")
    assert_not item.valid?
  end

  test "sets position automatically" do
    item = BuildItem.create!(user: @user, title: "First")
    assert_equal 1, item.position
    item2 = BuildItem.create!(user: @user, title: "Second")
    assert_equal 2, item2.position
  end

  test "pending scope returns incomplete items ordered by position" do
    i1 = BuildItem.create!(user: @user, title: "A", position: 2)
    i2 = BuildItem.create!(user: @user, title: "B", position: 1)
    i3 = BuildItem.create!(user: @user, title: "C", position: 3, completed: true, completed_at: Time.current)
    result = @user.build_items.pending
    assert_equal [i2, i1], result.to_a
  end

  test "completed scope returns done items" do
    i1 = BuildItem.create!(user: @user, title: "Done", completed: true, completed_at: Time.current)
    i2 = BuildItem.create!(user: @user, title: "Not done")
    result = @user.build_items.done
    assert_equal [i1], result.to_a
  end

  test "mark_completed! sets completed and timestamp" do
    item = BuildItem.create!(user: @user, title: "Todo")
    item.mark_completed!
    assert item.completed
    assert_not_nil item.completed_at
  end

  test "mark_pending! clears completed" do
    item = BuildItem.create!(user: @user, title: "Todo", completed: true, completed_at: Time.current)
    item.mark_pending!
    assert_not item.completed
    assert_nil item.completed_at
  end

  test "parses checklist items from markdown task list lines" do
    item = BuildItem.new(
      user: @user,
      title: "Grouped item",
      description: "Release prep\n- [ ] Write notes\n- [x] Ship build\n* [X] Verify logs"
    )

    assert_equal 3, item.checklist_total_count
    assert_equal 1, item.checklist_remaining_count
    assert_equal [1, 2, 3], item.checklist_items.map { |entry| entry[:line_index] }
  end

  test "toggles checklist items in description" do
    item = BuildItem.create!(
      user: @user,
      title: "Grouped item",
      description: "- [ ] Write notes\n- [x] Ship build"
    )

    item.toggle_checklist_item!(0)

    assert_includes item.reload.description, "- [x] Write notes"
    assert_equal 0, item.checklist_remaining_count
  end

  test "toggle checklist item ignores invalid line indexes" do
    item = BuildItem.create!(
      user: @user,
      title: "Grouped item",
      description: "- [ ] Write notes"
    )

    assert_not item.toggle_checklist_item!(-1)
    assert_not item.toggle_checklist_item!(9)
    assert_includes item.reload.description, "- [ ] Write notes"
  end

  test "does not allow completion while checklist items remain" do
    item = BuildItem.create!(
      user: @user,
      title: "Grouped item",
      description: "- [ ] Write notes"
    )

    assert_raises ActiveRecord::RecordInvalid do
      item.mark_completed!
    end
    assert_not item.reload.completed
  end

  test "pending scope floats pinned items to the top" do
    a = BuildItem.create!(user: @user, title: "A", position: 1)
    b = BuildItem.create!(user: @user, title: "B", position: 2, pinned: true)
    c = BuildItem.create!(user: @user, title: "C", position: 3)

    assert_equal [b, a, c], @user.build_items.pending.to_a
  end

  test "subitem_totals sums checklist lines across a collection" do
    i1 = BuildItem.new(description: "- [ ] one\n- [x] two")
    i2 = BuildItem.new(description: "- [x] three")
    i3 = BuildItem.new(description: "no checklist here")

    totals = BuildItem.subitem_totals([i1, i2, i3])
    assert_equal 3, totals[:total]
    assert_equal 2, totals[:done]
  end

  test "archive! marks completed without running checklist validation" do
    item = BuildItem.create!(user: @user, title: "Has open subs", description: "- [ ] open")
    item.archive!
    assert item.reload.completed
    assert_not_nil item.completed_at
  end

  test "absorb! folds another item in as a checklist subitem and destroys it" do
    target = BuildItem.create!(user: @user, title: "Parent", description: "intro")
    source = BuildItem.create!(user: @user, title: "Child", description: "- [ ] nested\nnote",
                               links: [{ "url" => "https://x.test", "label" => "X" }])

    target.absorb!(source)
    target.reload

    assert_not BuildItem.exists?(source.id)
    assert_includes target.description, "- [ ] Child"
    assert_includes target.description, "  - [ ] nested"
    assert_equal [{ "url" => "https://x.test", "label" => "X" }], target.links
  end

  test "absorb! merges links without duplicating by url" do
    link = { "url" => "https://dup.test", "label" => "Dup" }
    target = BuildItem.create!(user: @user, title: "Parent", links: [link])
    source = BuildItem.create!(user: @user, title: "Child", links: [link])

    target.absorb!(source)
    assert_equal 1, target.reload.links.size
  end

  test "absorb! refuses to absorb itself" do
    item = BuildItem.create!(user: @user, title: "Self")
    assert_raises(ArgumentError) { item.absorb!(item) }
  end
end
