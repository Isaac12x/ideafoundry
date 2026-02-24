require "test_helper"

class CoolOffTransitionJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
    @idea = Idea.create!(
      user: @user,
      title: "Test Idea",
      state: :incubating,
      attempt_count: 1,
      cool_off_until: 1.hour.ago  # Expired cool-off
    )
  end

  test "should transition idea from cool-off when expired" do
    assert @idea.cool_off_expired?
    assert_equal "incubating", @idea.state
    
    CoolOffTransitionJob.perform_now(@idea)
    
    @idea.reload
    assert_equal "triage", @idea.state
    assert_nil @idea.cool_off_until
  end

  test "should not transition idea if cool-off not expired" do
    @idea.update!(cool_off_until: 1.hour.from_now)
    
    assert_not @idea.cool_off_expired?
    
    CoolOffTransitionJob.perform_now(@idea)
    
    @idea.reload
    assert_equal "incubating", @idea.state
    assert_not_nil @idea.cool_off_until
  end

  test "should handle deleted idea gracefully" do
    @idea.destroy
    
    assert_nothing_raised do
      CoolOffTransitionJob.perform_now(@idea)
    end
  end
end