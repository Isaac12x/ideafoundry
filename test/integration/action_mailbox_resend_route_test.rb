require "test_helper"

class ActionMailboxResendRouteTest < ActionDispatch::IntegrationTest
  test "mounts resend inbound email webhook route" do
    post "/rails/action_mailbox/resend/inbound_emails",
         params: "{}",
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end
end
