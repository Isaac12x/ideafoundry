require "test_helper"

class LicensorContactTest < ActiveSupport::TestCase
  setup do
    @user = User.first || User.create!(email: "contact-test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Licensable Idea", for_licensing: true)
    @licensor = @idea.licensors.create!(company: "Acme")
  end

  test "defaults occurred_at and bumps the licensor's last_contacted_at" do
    assert_nil @licensor.last_contacted_at
    contact = @licensor.contacts.create!(channel: :email, summary: "Reached out")
    assert_not_nil contact.occurred_at
    assert_not_nil @licensor.reload.last_contacted_at
  end

  test "last_contacted_at tracks the most recent contact and recomputes on destroy" do
    older = @licensor.contacts.create!(channel: :email, occurred_at: 2.days.ago)
    newer = @licensor.contacts.create!(channel: :call, occurred_at: 1.day.ago)

    assert_in_delta newer.occurred_at.to_i, @licensor.reload.last_contacted_at.to_i, 1

    newer.destroy
    assert_in_delta older.occurred_at.to_i, @licensor.reload.last_contacted_at.to_i, 1

    older.destroy
    assert_nil @licensor.reload.last_contacted_at
  end
end
