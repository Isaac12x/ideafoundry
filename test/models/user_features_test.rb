require "test_helper"

class UserFeaturesTest < ActiveSupport::TestCase
  def setup
    @user = User.order(:id).first
  end

  test "features default to enabled" do
    assert User::FEATURE_KEYS.all? { |k| @user.feature_enabled?(k) }
  end

  test "disabling a feature persists and hides its nav item" do
    @user.update_features("licensing" => "0", "idea_states" => "1", "kb" => "1")

    assert_not @user.reload.feature_enabled?(:licensing)
    assert @user.feature_enabled?(:kb)
    assert_not_includes @user.nav_items_to_render, "licensing"
  ensure
    @user.update_features(User::FEATURE_KEYS.index_with { "1" })
  end

  test "nav order persists and unknown keys are dropped" do
    @user.update_display_quote("nav_order" => ["kb", "plan", "bogus"], "nav_visible" => User::NAV_PAGE_KEYS.index_with { "1" })

    order = @user.reload.nav_order
    assert_equal %w[kb plan], order.first(2)
    assert_equal User::NAV_PAGE_KEYS.sort, order.sort
  ensure
    @user.update_display_quote("nav_order" => User::NAV_PAGE_KEYS, "nav_visible" => User::NAV_PAGE_KEYS.index_with { "1" })
  end
end
