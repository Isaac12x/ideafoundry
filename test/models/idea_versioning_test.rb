require "test_helper"

class IdeaVersioningTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "versioning@example.com", name: "Versioning User")
    @idea = Idea.create!(
      user: @user,
      title: "Original idea",
      state: :first_try,
      trl: 3, difficulty: 4, opportunity: 8, timing: 6,
      metadata: { "custom_field" => "keep me" }
    )
    @idea.description = "Original description"
    @idea.save!
    @idea.todo_items.create!(title: "do a thing", position: 0)
    @idea.notes.create!(body: "a note", depth: 0)
  end

  test "unversioned idea reports versioned? false and empty idea_versions" do
    assert_not @idea.versioned?
    assert_empty @idea.idea_versions
  end

  test "create_new_version! deep-copies content into a linked primary version" do
    copy = @idea.create_new_version!
    @idea.reload

    # linkage
    assert_equal @idea.id, copy.version_group_id
    assert_equal @idea.id, @idea.version_group_id
    assert_equal 1, @idea.version_number
    assert_equal 2, copy.version_number
    assert_equal [@idea.id, copy.id].sort, @idea.idea_versions.pluck(:id).sort

    # new copy is primary, original is not
    assert copy.version_primary?
    assert_not @idea.version_primary?

    # content copied
    assert_equal "Original idea", copy.title
    assert_equal 8, copy.opportunity
    assert_equal "keep me", copy.metadata["custom_field"]
    assert_equal "Original description", copy.description.to_plain_text.strip
    assert_equal ["do a thing"], copy.todo_items.pluck(:title)
    assert_equal ["a note"], copy.notes.pluck(:body)

    # independent records, not shared
    assert_not_equal @idea.id, copy.id
    assert_not_equal @idea.todo_items.first.id, copy.todo_items.first.id
    assert_nil copy.integrity_hash
  end

  test "each version keeps its own history" do
    copy = @idea.create_new_version!
    copy.update!(title: "Edited copy title")
    @idea.update!(title: "Edited original title")

    assert copy.versions.any?
    assert @idea.versions.any?
    # editing the copy did not add history to the original and vice versa
    assert_not_includes @idea.versions.map(&:commit_message).join, "Edited copy"
  end

  test "primary_or_standalone scope hides non-primary versions" do
    copy = @idea.create_new_version!
    ids = @user.ideas.primary_or_standalone.pluck(:id)
    assert_includes ids, copy.id
    assert_not_includes ids, @idea.reload.id
  end

  test "make_primary_version! flips primary within the group" do
    copy = @idea.create_new_version!
    @idea.reload.make_primary_version!

    assert @idea.reload.version_primary?
    assert_not copy.reload.version_primary?
  end
end
