require "test_helper"

class VersionServiceTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "test@example.com", name: "Test User")
    @idea = Idea.create!(
      user: @user,
      title: "Test Idea",
      state: :idea_new,
      trl: 5,
      difficulty: 3,
      opportunity: 8,
      timing: 7
    )
    @service = VersionService.new(@idea)
  end

  test "should create version through service" do
    version = @service.create_version("Test version")
    
    assert version.persisted?
    assert_equal "Test version", version.commit_message
    assert_equal @idea, version.idea
  end

  test "should save with version in single transaction" do
    initial_count = @idea.versions.count
    
    result = @service.save_with_version(
      { title: "Updated Title", trl: 8 },
      "Updated title and TRL"
    )
    
    @idea.reload
    assert_equal "Updated Title", @idea.title
    assert_equal 8, @idea.trl
    assert_equal initial_count + 1, @idea.versions.count
    
    latest_version = @idea.latest_version
    assert_equal "Updated title and TRL", latest_version.commit_message
  end

  test "should rollback version if save fails" do
    initial_count = @idea.versions.count
    
    assert_raises(ActiveRecord::RecordInvalid) do
      @service.save_with_version(
        { title: nil }, # Invalid - title is required
        "This should fail"
      )
    end
    
    assert_equal initial_count, @idea.versions.count
  end

  test "should build version tree" do
    v1 = @service.create_version("Version 1")
    
    @idea.update!(title: "Title 2")
    v2 = Version.create_from_idea(@idea, "Version 2", v1)
    
    @idea.update!(title: "Title 3")
    v3 = Version.create_from_idea(@idea, "Version 3", v2)
    
    tree = @service.version_tree
    
    assert_equal 1, tree.size
    root_node = tree.first
    assert_equal v1, root_node[:version]
    assert_equal 1, root_node[:children].size
    assert_equal v2, root_node[:children].first[:version]
  end

  test "should compare two versions" do
    v1 = @service.create_version("Version 1")
    
    @idea.update!(title: "New Title", difficulty: 7)
    v2 = @service.create_version("Version 2")
    
    diff = @service.compare_versions(v1, v2)
    
    assert_includes diff.keys, 'title'
    assert_includes diff.keys, 'difficulty'
    assert_equal "Test Idea", diff['title'][:from]
    assert_equal "New Title", diff['title'][:to]
  end

  test "should raise error when comparing versions from different ideas" do
    other_idea = Idea.create!(user: @user, title: "Other Idea", state: :idea_new)
    other_version = Version.create_from_idea(other_idea, "Other version")
    
    v1 = @service.create_version("Version 1")
    
    assert_raises(ArgumentError) do
      @service.compare_versions(v1, other_version)
    end
  end

  test "should restore version through service" do
    v1 = @service.create_version("Version 1")
    
    @idea.update!(title: "Modified Title", trl: 9)
    @service.create_version("Version 2")
    
    @service.restore_version(v1)
    @idea.reload
    
    assert_equal "Test Idea", @idea.title
    assert_equal 5, @idea.trl
  end

  test "should raise error when restoring version from different idea" do
    other_idea = Idea.create!(user: @user, title: "Other Idea", state: :idea_new)
    other_version = Version.create_from_idea(other_idea, "Other version")
    
    assert_raises(ArgumentError) do
      @service.restore_version(other_version)
    end
  end

  test "should generate timeline" do
    v1 = @service.create_version("Version 1")
    sleep 0.01
    
    @idea.update!(title: "Title 2")
    v2 = @service.create_version("Version 2")
    sleep 0.01
    
    @idea.update!(title: "Title 3")
    v3 = @service.create_version("Version 3")
    
    timeline = @service.timeline
    
    assert_equal 3, timeline.size
    assert_equal v1.id, timeline[0][:id]
    assert_equal v2.id, timeline[1][:id]
    assert_equal v3.id, timeline[2][:id]
    
    assert timeline[0][:is_root]
    assert_not timeline[1][:is_root]
  end

  test "should include branch information in timeline" do
    v1 = @service.create_version("Parent")
    
    @idea.update!(title: "Branch 1")
    v2 = Version.create_from_idea(@idea, "Branch 1", v1)
    
    @idea.update!(title: "Branch 2")
    v3 = Version.create_from_idea(@idea, "Branch 2", v1)
    
    timeline = @service.timeline
    
    parent_entry = timeline.find { |entry| entry[:id] == v1.id }
    assert parent_entry[:has_branches]
  end
end
