require "test_helper"

class VersionControlWorkflowTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "test@example.com", name: "Test User")
    @idea = Idea.create!(
      user: @user,
      title: "My Product Idea",
      state: :idea_new,
      category: "SaaS",
      trl: 3,
      difficulty: 5,
      opportunity: 8,
      timing: 6
    )
    @idea.description = "Initial description of the product"
    @idea.save!
  end

  test "complete version control workflow" do
    # Step 1: Create initial version
    v1 = @idea.create_version("Initial version")
    assert_equal 1, @idea.versions.count
    assert v1.root?
    assert_equal "My Product Idea", v1.snapshot_data['title']

    # Step 2: Make changes and create second version
    @idea.update!(title: "Improved Product Idea", trl: 5)
    v2 = @idea.create_version("Improved title and increased TRL")
    
    assert_equal 2, @idea.versions.count
    assert_equal v1, v2.parent_version
    assert_not_nil v2.diff_summary
    assert_includes v2.diff_summary, "title:"
    assert_includes v2.diff_summary, "trl:"

    # Step 3: Make more changes
    @idea.update!(opportunity: 9, timing: 8, category: "B2B SaaS")
    v3 = @idea.create_version("Updated scoring and category")
    
    assert_equal 3, @idea.versions.count
    assert_equal v2, v3.parent_version

    # Step 4: Compare versions
    diff = v3.diff_with(v1)
    assert_includes diff.keys, 'title'
    assert_includes diff.keys, 'opportunity'
    assert_includes diff.keys, 'category'
    assert_equal "My Product Idea", diff['title'][:from]
    assert_equal "Improved Product Idea", diff['title'][:to]

    # Step 5: Restore to v1 (creates a branch)
    v1.restore_to_idea!
    @idea.reload
    
    assert_equal "My Product Idea", @idea.title
    assert_equal 3, @idea.trl
    assert_equal "SaaS", @idea.category
    
    # Should have created a new version for the restoration
    assert_equal 4, @idea.versions.count
    restoration_version = @idea.latest_version
    assert_includes restoration_version.commit_message, "Restored from version"
    assert_equal v1, restoration_version.parent_version

    # Step 6: Verify version tree structure
    service = VersionService.new(@idea)
    tree = service.version_tree
    
    assert_equal 1, tree.size # One root
    root_node = tree.first
    assert_equal v1, root_node[:version]
    
    # v1 should have two children: v2 and the restoration
    assert_equal 2, root_node[:children].size

    # Step 7: Get timeline
    timeline = service.timeline
    assert_equal 4, timeline.size
    assert timeline[0][:is_root]
    assert timeline[0][:has_branches]

    # Step 8: Use VersionService for atomic update
    service.save_with_version(
      { title: "Final Product Name", state: :validated },
      "Finalized product name and validated"
    )
    
    @idea.reload
    assert_equal "Final Product Name", @idea.title
    assert_equal "validated", @idea.state
    assert_equal 5, @idea.versions.count
  end

  test "branching workflow" do
    # Create initial version
    v1 = @idea.create_version("Initial")
    
    # Create first branch
    @idea.update!(title: "Branch A")
    v2a = @idea.create_version("Branch A changes")
    
    # Go back to v1 and create second branch
    v1.restore_to_idea!
    @idea.reload
    restoration = @idea.latest_version
    
    @idea.update!(title: "Branch B")
    v2b = @idea.create_version("Branch B changes")
    
    # Verify tree structure
    assert v1.has_branches?
    assert_equal 2, v1.child_versions.count
    
    # Verify both branches exist
    descendants = v1.descendants
    assert_includes descendants.map(&:id), v2a.id
    assert_includes descendants.map(&:id), restoration.id
    assert_includes descendants.map(&:id), v2b.id
  end

  test "version history preservation" do
    # Create multiple versions
    versions = []
    5.times do |i|
      @idea.update!(trl: i + 1)
      versions << @idea.create_version("Version #{i + 1}")
      sleep 0.01 # Ensure different timestamps
    end
    
    # Verify history is preserved
    history = @idea.version_history.to_a
    assert_equal 5, history.size
    assert_equal versions, history
    
    # Verify ancestry path
    last_version = versions.last
    path = last_version.ancestry_path
    assert_equal 5, path.size
    assert_equal versions, path
  end
end
