require "test_helper"

class CleanOrphanedDraftsJobTest < ActiveJob::TestCase
  def setup
    @user = User.first
  end

  test "removes only old untouched blank drafts and preserves meaningful drafts" do
    blank = @user.ideas.create!(state: :idea_new, draft: true)
    untouched = @user.ideas.create!(state: :idea_new, draft: true)
    old_title = @user.ideas.create!(title: "old draft", state: :idea_new, draft: true)
    old_location = @user.ideas.create!(location: "Lisbon", state: :idea_new, draft: true)
    old_situation = @user.ideas.create!(situation: "After the meeting", state: :idea_new, draft: true)
    old_time = 2.days.ago
    Idea.where(id: [ blank.id, untouched.id, old_title.id, old_location.id, old_situation.id ]).update_all(created_at: old_time, updated_at: old_time)
    untouched.update_column(:updated_at, 1.day.ago)
    assert_equal blank.created_at, blank.updated_at

    assert_difference("Idea.count", -1) do
      CleanOrphanedDraftsJob.perform_now
    end
    assert_nil Idea.find_by(id: blank.id)
    [ untouched, old_title, old_location, old_situation ].each { |idea| assert Idea.find_by(id: idea.id), "expected draft #{idea.id} to remain" }
  end

  test "leaves non-drafts untouched" do
    real = @user.ideas.create!(title: "real", state: :idea_new, draft: false)
    Idea.where(id: real.id).update_all(updated_at: 5.days.ago)

    assert_no_difference("Idea.count") do
      CleanOrphanedDraftsJob.perform_now
    end
  end
end
