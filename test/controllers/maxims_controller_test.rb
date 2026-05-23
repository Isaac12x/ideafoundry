require "test_helper"

class MaximsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
  end

  test "creates a maxim for the current user" do
    assert_difference -> { @user.reload.maxims.count }, 1 do
      post maxims_path, params: { maxim: { body: "Keep the constraint visible." } }
    end

    assert_redirected_to kb_path(tab: "maxims")
    assert_equal "Keep the constraint visible.", @user.reload.maxims.recent.first.body
  end

  test "destroys a maxim for the current user" do
    maxim = @user.maxims.create!(body: "Delete this maxim.")

    assert_difference -> { @user.reload.maxims.count }, -1 do
      delete maxim_path(maxim)
    end

    assert_redirected_to kb_path(tab: "maxims")
  end
end
