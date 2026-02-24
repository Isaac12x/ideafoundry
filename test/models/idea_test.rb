require "test_helper"

class IdeaTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @idea = Idea.new(
      user: @user,
      title: "Test Idea",
      trl: 5,
      difficulty: 3,
      opportunity: 8,
      timing: 6
    )
  end

  test "should be valid with valid attributes" do
    assert @idea.valid?
  end

  test "should require title" do
    @idea.title = nil
    assert_not @idea.valid?
    assert_includes @idea.errors[:title], "can't be blank"
  end

  test "should require user" do
    @idea.user = nil
    assert_not @idea.valid?
    assert_includes @idea.errors[:user], "must exist"
  end

  test "should set default values on create" do
    idea = Idea.create!(user: @user, title: "New Idea")
    assert_equal "idea_new", idea.state
    assert_equal 0, idea.attempt_count
    assert_equal 0, idea.trl
    assert_equal 0, idea.difficulty
    assert_equal 0, idea.opportunity
    assert_equal 0, idea.timing
  end

  test "should validate scoring attributes range" do
    @idea.trl = 11
    assert_not @idea.valid?
    assert_includes @idea.errors[:trl], "is not included in the list"

    @idea.trl = -1
    assert_not @idea.valid?
    assert_includes @idea.errors[:trl], "is not included in the list"
  end

  test "should calculate score automatically" do
    @idea.save!
    expected_score = (5 * 0.3 + 8 * 0.4 + 6 * 0.2 - 3 * 0.1).round(2)
    assert_equal expected_score, @idea.computed_score
  end

  test "should have valid state enum" do
    Idea.states.each do |state, _|
      @idea.state = state
      assert @idea.valid?, "State #{state} should be valid"
    end
  end

  test "should have many idea_lists" do
    assert_respond_to @idea, :idea_lists
  end

  test "should have many lists through idea_lists" do
    assert_respond_to @idea, :lists
  end

  test "should have active scope" do
    active_idea = Idea.create!(user: @user, title: "Active", state: :idea_new)
    rejected_idea = Idea.create!(user: @user, title: "Rejected", state: :rejected)
    
    assert_includes Idea.active, active_idea
    assert_not_includes Idea.active, rejected_idea
  end

  test "should have by_state scope" do
    new_idea = Idea.create!(user: @user, title: "New", state: :idea_new)
    triage_idea = Idea.create!(user: @user, title: "Triage", state: :triage)
    
    new_ideas = Idea.by_state(:idea_new)
    assert_includes new_ideas, new_idea
    assert_not_includes new_ideas, triage_idea
  end

  # CRUD operation tests
  test "should create idea with valid attributes" do
    idea = Idea.create!(
      user: @user,
      title: "New Product Idea",
      category: "SaaS",
      trl: 4,
      difficulty: 6,
      opportunity: 7,
      timing: 5
    )
    
    assert idea.persisted?
    assert_equal "New Product Idea", idea.title
    assert_equal "SaaS", idea.category
    assert_equal "idea_new", idea.state
  end

  test "should read idea attributes" do
    idea = Idea.create!(user: @user, title: "Test Read")
    retrieved_idea = Idea.find(idea.id)
    
    assert_equal idea.title, retrieved_idea.title
    assert_equal idea.user_id, retrieved_idea.user_id
  end

  test "should update idea attributes" do
    idea = Idea.create!(user: @user, title: "Original Title")
    idea.update!(title: "Updated Title", category: "Updated Category")
    
    idea.reload
    assert_equal "Updated Title", idea.title
    assert_equal "Updated Category", idea.category
  end

  test "should delete idea" do
    idea = Idea.create!(user: @user, title: "To Delete")
    idea_id = idea.id
    idea_count = Idea.count
    
    idea.destroy
    assert_equal idea_count - 1, Idea.count
    assert_raises(ActiveRecord::RecordNotFound) do
      Idea.find(idea_id)
    end
  end

  # State transition tests (Requirements 3.1, 3.2)
  test "should transition from new to first_try" do
    idea = Idea.create!(user: @user, title: "Test Transition", state: :idea_new)
    
    assert idea.transition_to_first_try!
    assert_equal "first_try", idea.state
    assert_equal 1, idea.attempt_count
  end

  test "should transition from triage to first_try" do
    idea = Idea.create!(user: @user, title: "Test Transition", state: :triage)
    
    assert idea.transition_to_first_try!
    assert_equal "first_try", idea.state
    assert_equal 1, idea.attempt_count
  end

  test "should not transition to first_try from invalid state" do
    idea = Idea.create!(user: @user, title: "Test Transition", state: :validated)
    
    assert_not idea.transition_to_first_try!
    assert_equal "validated", idea.state
  end

  test "should transition to second_try after first attempt" do
    idea = Idea.create!(user: @user, title: "Test Transition", state: :triage, attempt_count: 1)
    
    assert idea.transition_to_second_try!
    assert_equal "second_try", idea.state
    assert_equal 2, idea.attempt_count
  end

  # Cool-off period tests (Requirements 3.3, 3.4)
  test "should enter cool-off period on failed attempt" do
    idea = Idea.create!(user: @user, title: "Test Cool-off", state: :first_try)
    
    assert idea.fail_attempt!(2.days)
    assert_equal "incubating", idea.state
    assert idea.cool_off_until.present?
    assert idea.in_cool_off?
  end

  test "should not allow editing during cool-off period" do
    idea = Idea.create!(user: @user, title: "Test Cool-off", state: :first_try)
    idea.fail_attempt!(2.days)
    
    assert_not idea.can_edit_content?
    assert idea.can_edit? # Can still edit notes in incubating state
  end

  test "should detect expired cool-off period" do
    idea = Idea.create!(user: @user, title: "Test Cool-off", state: :incubating)
    idea.update!(cool_off_until: 1.day.ago)
    
    assert idea.cool_off_expired?
    assert_not idea.in_cool_off?
  end

  test "should reopen idea after cool-off expires" do
    idea = Idea.create!(
      user: @user,
      title: "Test Reopen",
      state: :incubating,
      attempt_count: 1
    )
    idea.update_column(:cool_off_until, 1.day.ago)
    idea.reload
    
    assert idea.reopen_from_cool_off!
    idea.reload
    assert_equal "triage", idea.state
    assert_nil idea.cool_off_until
  end

  # Additional state transition tests
  test "should complete attempt successfully" do
    idea = Idea.create!(user: @user, title: "Test Complete", state: :first_try)
    
    assert idea.complete_attempt!
    assert_equal "validated", idea.state
    assert_nil idea.cool_off_until
  end

  test "should park idea" do
    idea = Idea.create!(user: @user, title: "Test Park", state: :triage)
    
    assert idea.park!
    assert_equal "parked", idea.state
  end

  test "should reject idea" do
    idea = Idea.create!(user: @user, title: "Test Reject", state: :triage)
    
    assert idea.reject!
    assert_equal "rejected", idea.state
  end

  test "should ship validated idea" do
    idea = Idea.create!(user: @user, title: "Test Ship", state: :validated)
    
    assert idea.ship!
    assert_equal "shipped", idea.state
  end

  test "should not ship non-validated idea" do
    idea = Idea.create!(user: @user, title: "Test Ship", state: :triage)
    
    assert_not idea.ship!
    assert_equal "triage", idea.state
  end

  # Relationship tests (Requirement 1.4)
  test "should belong to multiple lists" do
    idea = Idea.create!(user: @user, title: "Multi-list Idea")
    list1 = List.create!(user: @user, name: "List 1")
    list2 = List.create!(user: @user, name: "List 2")
    
    idea.lists << list1
    idea.lists << list2
    
    assert_equal 2, idea.lists.count
    assert_includes idea.lists, list1
    assert_includes idea.lists, list2
  end

  test "should cascade delete idea_lists when idea is deleted" do
    idea = Idea.create!(user: @user, title: "Test Cascade")
    list = List.create!(user: @user, name: "Test List")
    idea_list = IdeaList.create!(idea: idea, list: list)
    
    idea_list_count = IdeaList.count
    idea.destroy
    
    assert_equal idea_list_count - 1, IdeaList.count
    assert_not IdeaList.exists?(idea_id: idea.id)
  end

  # Version control tests (Requirements 5.1, 5.2, 5.3, 5.4, 5.5)
  test "should create version with commit message" do
    idea = Idea.create!(user: @user, title: "Versioned Idea")
    version = idea.create_version("Initial version")
    
    assert version.persisted?
    assert_equal "Initial version", version.commit_message
    assert_equal idea, version.idea
  end

  test "should get latest version" do
    idea = Idea.create!(user: @user, title: "Versioned Idea")
    v1 = idea.create_version("Version 1")
    sleep 0.01
    v2 = idea.create_version("Version 2")
    
    assert_equal v2, idea.latest_version
  end

  test "should get version history in chronological order" do
    idea = Idea.create!(user: @user, title: "Versioned Idea")
    v1 = idea.create_version("Version 1")
    sleep 0.01
    v2 = idea.create_version("Version 2")
    sleep 0.01
    v3 = idea.create_version("Version 3")
    
    history = idea.version_history.to_a
    assert_equal [v1, v2, v3], history
  end

  test "should restore version through idea" do
    idea = Idea.create!(user: @user, title: "Original Title", trl: 5)
    first_version = idea.create_version("First version")
    
    idea.update!(title: "Modified Title", trl: 8)
    idea.create_version("Second version")
    
    idea.restore_version(first_version)
    idea.reload
    
    assert_equal "Original Title", idea.title
    assert_equal 5, idea.trl
  end

  test "should not restore version from different idea" do
    idea1 = Idea.create!(user: @user, title: "Idea 1")
    idea2 = Idea.create!(user: @user, title: "Idea 2")
    
    version1 = idea1.create_version("Version 1")
    
    assert_raises(ArgumentError) do
      idea2.restore_version(version1)
    end
  end

  test "should have many versions" do
    idea = Idea.create!(user: @user, title: "Versioned Idea")
    
    assert_respond_to idea, :versions
    assert_equal 0, idea.versions.count
    
    idea.create_version("V1")
    idea.create_version("V2")
    
    assert_equal 2, idea.versions.count
  end

  test "should cascade delete versions when idea is deleted" do
    idea = Idea.create!(user: @user, title: "Test Cascade")
    idea.create_version("Version 1")
    idea.create_version("Version 2")
    
    version_count = Version.count
    idea.destroy
    
    assert_equal version_count - 2, Version.count
  end
end
