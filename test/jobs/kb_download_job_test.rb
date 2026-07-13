require "test_helper"

class KbDownloadJobTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
  end

  test "marks failed when the source index does not exist" do
    dl = @user.kb_downloads.create!(source_index: 999, dir: "", url: "https://x.com/f.pdf",
                                    format: "auto", status: "pending")
    # No network/yt-dlp is reached: the source guard fails first.
    assert_nothing_raised { KbDownloadJob.perform_now(dl.id) }
    assert_equal "failed", dl.reload.status
    assert_match(/not available/i, dl.error)
  end

  test "no-ops when the download was deleted" do
    assert_nothing_raised { KbDownloadJob.perform_now(-1) }
  end

  test "no-ops when the download is already terminal" do
    dl = @user.kb_downloads.create!(source_index: 0, dir: "", url: "https://x.com/f.pdf",
                                    format: "auto", status: "done", filename: "f.pdf")
    KbDownloadJob.perform_now(dl.id)
    assert_equal "done", dl.reload.status
  end
end
