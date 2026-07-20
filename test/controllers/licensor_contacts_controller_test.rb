require "test_helper"

class LicensorContactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "lcc-test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Licensable Idea", for_licensing: true)
    @licensor = @idea.licensors.create!(company: "Acme")
  end

  test "logging a contact from the panel bumps last_contacted and returns panel + board" do
    assert_difference("LicensorContact.count", 1) do
      post licensor_contacts_path(@licensor, format: :turbo_stream),
           params: { context: "panel", licensor_contact: { channel: "email", summary: "Intro" } }
    end
    assert_response :success
    assert_not_nil @licensor.reload.last_contacted_at
    assert_match "licensor-panel", response.body
    assert_match "crm-board", response.body
  end

  test "logging a contact from the tab returns the tab stream" do
    post licensor_contacts_path(@licensor, format: :turbo_stream),
         params: { context: "tab", licensor_contact: { channel: "call" } }
    assert_response :success
    assert_match "licensors_tab_#{@idea.id}", response.body
  end

  test "destroying a contact recomputes last_contacted" do
    contact = @licensor.contacts.create!(channel: :email, occurred_at: 1.day.ago)
    assert_difference("LicensorContact.count", -1) do
      delete licensor_contact_path(@licensor, contact, format: :turbo_stream), params: { context: "panel" }
    end
    assert_response :success
    assert_nil @licensor.reload.last_contacted_at
  end
end
