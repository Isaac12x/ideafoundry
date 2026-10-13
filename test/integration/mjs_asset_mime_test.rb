require "test_helper"

class MjsAssetMimeTest < ActiveSupport::TestCase
  test "mjs assets resolve to javascript mime type" do
    asset = Rails.application.assets.find_asset("lib/excalidraw_loader.mjs")
    assert_equal "application/javascript", asset.content_type
  end
end
