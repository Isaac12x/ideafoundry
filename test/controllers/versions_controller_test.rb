require "test_helper"

class VersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @idea = ideas(:one)
    @idea.update!(user: @user)
    
    # Create some versions for testing
    @version1 = Version.create_from_idea(@idea, "Initial version")
    @idea.update!(title: "Updated Title")
    @version2 = Version.create_from_idea(@idea, "Updated title", @version1)
    @idea.update!(description: "New description")
    @version3 = Version.create_from_idea(@idea, "Added description", @version2)
  end

  test "should get index" do
    get idea_versions_url(@idea)
    assert_response :success
    assert_select "h1", "Version History"
    assert_select ".timeline-item", @idea.versions.count
  end

  test "should show version" do
    get idea_version_url(@idea, @version2)
    assert_response :success
    assert_select "h2", @version2.commit_message
    assert_select ".snapshot-table"
  end

  test "should show diff on version detail page" do
    get idea_version_url(@idea, @version2)
    assert_response :success
    assert_select ".diff-display" if @version2.parent_version
  end

  test "should get compare page" do
    get compare_idea_versions_url(@idea, from: @version1.id, to: @version2.id)
    assert_response :success
    assert_select ".version-compare-container"
    assert_select ".from-version"
    assert_select ".to-version"
  end

  test "should show side by side diff on compare page" do
    get compare_idea_versions_url(@idea, from: @version1.id, to: @version2.id)
    assert_response :success
    
    diff = @version2.diff_with(@version1)
    if diff.any?
      assert_select ".side-by-side-diff"
      assert_select ".diff-item", diff.keys.length
    end
  end

  test "should restore version" do
    original_title = @idea.title
    
    post restore_idea_version_url(@idea, @version1)
    assert_redirected_to idea_path(@idea)
    
    @idea.reload
    assert_equal @version1.snapshot_data['title'], @idea.title
    assert_not_equal original_title, @idea.title
    
    # Should create a new version for the restoration
    assert @idea.versions.where("commit_message LIKE ?", "%Restored from version%").exists?
  end

  test "should show confirmation message after restore" do
    post restore_idea_version_url(@idea, @version1)
    assert_redirected_to idea_path(@idea)
    assert_equal "Version restored successfully. A new version has been created.", flash[:notice]
  end

  test "should handle invalid version comparison gracefully" do
    get compare_idea_versions_url(@idea, from: 99999, to: @version2.id)
    assert_redirected_to idea_versions_path(@idea)
    follow_redirect!
    assert_select ".alert.alert-error", /invalid version/i
  end

  test "should show no changes message when comparing identical versions" do
    # Create two identical versions
    @idea.update!(title: "Same Title")
    version_a = Version.create_from_idea(@idea, "Version A")
    version_b = Version.create_from_idea(@idea, "Version B")
    
    get compare_idea_versions_url(@idea, from: version_a.id, to: version_b.id)
    assert_response :success
    
    diff = version_b.diff_with(version_a)
    if diff.empty?
      assert_select ".no-changes"
    end
  end

  test "should display timeline with correct order" do
    get idea_versions_url(@idea)
    assert_response :success
    
    # Versions should be in chronological order
    versions = @idea.versions.chronological
    assert_equal versions.first.id, @version1.id
    assert_equal versions.last.id, @version3.id
  end

  test "should show parent version link on detail page" do
    get idea_version_url(@idea, @version2)
    assert_response :success
    
    if @version2.parent_version
      assert_select "a[href=?]", idea_version_path(@idea, @version2.parent_version)
    end
  end

  test "should show child versions on detail page" do
    get idea_version_url(@idea, @version2)
    assert_response :success
    
    if @version2.child_versions.any?
      assert_select ".children-info"
      @version2.child_versions.each do |child|
        assert_select "a[href=?]", idea_version_path(@idea, child)
      end
    end
  end

  test "should show restore button with confirmation" do
    get idea_version_url(@idea, @version1)
    assert_response :success
    assert_select "form[action=?]", restore_idea_version_path(@idea, @version1)
    assert_select "form[data-turbo-confirm]"
  end

  test "should show compare with parent button when parent exists" do
    get idea_version_url(@idea, @version2)
    assert_response :success
    
    if @version2.parent_version
      assert_select "a[href=?]", compare_idea_versions_path(@idea, from: @version2.parent_version_id, to: @version2.id)
    end
  end

  test "should indicate root version" do
    get idea_version_url(@idea, @version1)
    assert_response :success
    
    if @version1.root?
      assert_select ".root-info"
      assert_select ".badge", "Root Version"
    end
  end

  test "should show branch indicator for versions with children" do
    get idea_versions_url(@idea)
    assert_response :success
    
    @idea.versions.each do |version|
      if version.has_branches?
        # Timeline item should have has-branches class
        assert_select ".timeline-item.has-branches"
      end
    end
  end
end
