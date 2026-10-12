require "test_helper"

class LocalAgent::WorkDiscoveryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @dl = @user.kb_downloads.create!(source_index: 0, url: "https://youtu.be/abc", title: "Talk", status: "done",
                                     transcript: "00:01 - hi", transcript_status: "done")
  end

  def digest_work = LocalAgent::WorkDiscovery.new(@user).list(limit: 100).select { |c| c[:target_type] == "KbDownload" }

  test "transcript without digest is work until digested" do
    assert_equal [@dl.id], digest_work.map { |c| c[:target_id] }
    MediaDigest.record!(user: @user, kb_download: @dl, body: "- fact")
    assert_empty digest_work
  end

  test "pending transcript is not work" do
    @dl.update!(transcript_status: "pending")
    assert_empty digest_work
  end
end
