require "test_helper"

class CleanOrphanedDraftsJobTest < ActiveJob::TestCase
  def setup
    @user = User.first
  end

  test "destroys drafts older than the threshold" do
    fresh = @user.ideas.create!(title: "fresh draft", state: :idea_new, draft: true)
    old = @user.ideas.create!(title: "old draft", state: :idea_new, draft: true)
    Idea.where(id: old.id).update_all(updated_at: 2.days.ago)

    assert_difference("Idea.count", -1) do
      CleanOrphanedDraftsJob.perform_now
    end
    assert_nil Idea.find_by(id: old.id)
    assert Idea.find_by(id: fresh.id)
  end

  test "leaves non-drafts untouched" do
    real = @user.ideas.create!(title: "real", state: :idea_new, draft: false)
    Idea.where(id: real.id).update_all(updated_at: 5.days.ago)

    assert_no_difference("Idea.count") do
      CleanOrphanedDraftsJob.perform_now
    end
  end
end
