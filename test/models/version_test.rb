require "test_helper"

class VersionTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "test@example.com", name: "Test User")
    @idea = Idea.create!(
      user: @user,
      title: "Original Title",
      state: :idea_new,
      category: "Tech",
      trl: 5,
      difficulty: 3,
      opportunity: 8,
      timing: 7
    )
    @idea.description = "Original description"
    @idea.save!
  end

  test "should create version with snapshot" do
    version = Version.create_from_idea(@idea, "Initial version")
    
    assert version.persisted?
    assert_equal "Initial version", version.commit_message
    assert_not_nil version.snapshot_data
    assert_equal @idea.title, version.snapshot_data['title']
    assert_equal @idea.state, version.snapshot_data['state']
  end

  test "should create version with parent relationship" do
    first_version = Version.create_from_idea(@idea, "First version")
    
    @idea.update!(title: "Updated Title")
    second_version = Version.create_from_idea(@idea, "Second version", first_version)
    
    assert_equal first_version, second_version.parent_version
    assert_includes first_version.child_versions, second_version
  end

  test "should generate snapshot automatically" do
    version = Version.new(idea: @idea, commit_message: "Test")
    version.save!
    
    assert_not_nil version.snapshot_data
    assert_equal @idea.title, version.snapshot_data['title']
    assert_equal @idea.trl, version.snapshot_data['trl']
  end

  test "should generate diff summary when parent exists" do
    first_version = Version.create_from_idea(@idea, "First version")
    
    @idea.update!(title: "New Title", trl: 7)
    second_version = Version.create_from_idea(@idea, "Second version", first_version)
    
    assert_not_nil second_version.diff_summary
    assert_includes second_version.diff_summary, "title:"
    assert_includes second_version.diff_summary, "trl:"
  end

  test "should not generate diff summary for root version" do
    version = Version.create_from_idea(@idea, "Root version")
    
    assert_nil version.diff_summary
  end

  test "should compare versions with diff_with" do
    first_version = Version.create_from_idea(@idea, "First version")
    
    @idea.update!(title: "Changed Title", difficulty: 5)
    second_version = Version.create_from_idea(@idea, "Second version", first_version)
    
    diff = second_version.diff_with(first_version)
    
    # Should have title, difficulty, and computed_score changes
    assert diff.keys.size >= 2
    assert_equal "Original Title", diff['title'][:from]
    assert_equal "Changed Title", diff['title'][:to]
    assert_equal 3, diff['difficulty'][:from]
    assert_equal 5, diff['difficulty'][:to]
  end

  test "should restore version to idea" do
    first_version = Version.create_from_idea(@idea, "First version")
    
    @idea.update!(title: "Modified Title", trl: 9)
    second_version = Version.create_from_idea(@idea, "Second version", first_version)
    
    # Restore first version
    first_version.restore_to_idea!
    @idea.reload
    
    assert_equal "Original Title", @idea.title
    assert_equal 5, @idea.trl
  end

  test "should create new version when restoring" do
    first_version = Version.create_from_idea(@idea, "First version")
    
    @idea.update!(title: "Modified Title")
    Version.create_from_idea(@idea, "Second version", first_version)
    
    initial_count = @idea.versions.count
    first_version.restore_to_idea!
    
    assert_equal initial_count + 1, @idea.versions.count
    latest = @idea.versions.order(created_at: :desc).first
    assert_includes latest.commit_message, "Restored from version"
  end

  test "should build ancestry path" do
    v1 = Version.create_from_idea(@idea, "Version 1")
    
    @idea.update!(title: "Title 2")
    v2 = Version.create_from_idea(@idea, "Version 2", v1)
    
    @idea.update!(title: "Title 3")
    v3 = Version.create_from_idea(@idea, "Version 3", v2)
    
    path = v3.ancestry_path
    assert_equal 3, path.size
    assert_equal [v1, v2, v3], path
  end

  test "should identify root version" do
    root_version = Version.create_from_idea(@idea, "Root")
    
    @idea.update!(title: "Updated")
    child_version = Version.create_from_idea(@idea, "Child", root_version)
    
    assert root_version.root?
    assert_not child_version.root?
  end

  test "should detect branches" do
    parent = Version.create_from_idea(@idea, "Parent")
    
    @idea.update!(title: "Branch 1")
    child1 = Version.create_from_idea(@idea, "Child 1", parent)
    
    @idea.update!(title: "Branch 2")
    child2 = Version.create_from_idea(@idea, "Child 2", parent)
    
    assert parent.has_branches?
    assert_not child1.has_branches?
  end

  test "should get all descendants" do
    v1 = Version.create_from_idea(@idea, "V1")
    
    @idea.update!(title: "V2")
    v2 = Version.create_from_idea(@idea, "V2", v1)
    
    @idea.update!(title: "V3")
    v3 = Version.create_from_idea(@idea, "V3", v2)
    
    descendants = v1.descendants
    assert_equal 2, descendants.size
    assert_includes descendants, v2
    assert_includes descendants, v3
  end

  test "should validate presence of commit_message" do
    version = Version.new(idea: @idea, commit_message: nil)
    assert_not version.valid?
    assert_includes version.errors[:commit_message], "can't be blank"
  end

  test "should validate presence of snapshot_data" do
    version = Version.new(idea: @idea, commit_message: "Test", snapshot_data: nil)
    version.save
    # Should auto-generate snapshot, so it should be valid
    assert version.valid?
  end

  test "should scope versions for idea" do
    idea2 = Idea.create!(user: @user, title: "Another Idea", state: :idea_new)
    
    v1 = Version.create_from_idea(@idea, "Idea 1 Version")
    v2 = Version.create_from_idea(idea2, "Idea 2 Version")
    
    versions = Version.for_idea(@idea)
    assert_includes versions, v1
    assert_not_includes versions, v2
  end

  test "should order versions chronologically" do
    v1 = Version.create_from_idea(@idea, "First")
    sleep 0.01
    v2 = Version.create_from_idea(@idea, "Second")
    sleep 0.01
    v3 = Version.create_from_idea(@idea, "Third")
    
    chronological = Version.chronological.to_a
    assert_equal [v1, v2, v3], chronological
  end

  test "should preserve description in snapshot" do
    @idea.description = "Rich text description"
    @idea.save!
    
    version = Version.create_from_idea(@idea, "With description")
    
    assert_equal "Rich text description", version.snapshot_data['description']
  end

  test "should restore description from version" do
    @idea.description = "Original description"
    @idea.save!
    
    first_version = Version.create_from_idea(@idea, "First")
    
    @idea.description = "Modified description"
    @idea.save!
    
    first_version.restore_to_idea!
    @idea.reload
    
    assert_equal "Original description", @idea.description.to_plain_text
  end
end
