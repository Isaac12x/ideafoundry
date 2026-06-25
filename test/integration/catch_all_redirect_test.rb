require "test_helper"

class CatchAllRedirectTest < ActionDispatch::IntegrationTest
  # The catch-all must use a TEMPORARY redirect. A 301 (permanent) gets cached by
  # browsers forever, so any transiently-unmatched path (source maps, stale asset
  # digests) permanently resolves to "/" -> redirect loops + "failed to fetch module".
  test "unmatched path redirects to root with 302, not 301" do
    get "/some/unknown/page"
    assert_response :found # 302
    assert_redirected_to "/"
  end

  # Missing asset paths must NOT be redirected to the HTML home page; a dynamic
  # import of such a URL would receive HTML and fail. They should 404 instead.
  test "missing /assets path is not redirected to root" do
    get "/assets/controllers/does_not_exist-deadbeef.js"
    assert_not_equal "/", (response.location && URI(response.location).path),
      "missing asset should not redirect to /"
    assert_includes [404, 200], response.status
  end
end
