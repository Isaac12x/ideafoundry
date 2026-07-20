require "test_helper"

class KbDownloadTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
  end

  test "enqueue creates a pending record and enqueues the job" do
    assert_enqueued_with(job: KbDownloadJob) do
      dl = KbDownload.enqueue(user: @user, source_index: 0, dir: "notes",
                              url: "https://youtu.be/abc", format: "audio")
      assert dl.persisted?
      assert_equal "pending", dl.status
      assert_equal "audio", dl.format
      assert_equal "notes", dl.dir
    end
  end

  test "invalid format falls back to auto" do
    dl = KbDownload.enqueue(user: @user, source_index: 0, dir: "", url: "https://x.com/f.pdf", format: "junk")
    assert_equal "auto", dl.format
  end

  test "rejects non-http urls" do
    dl = KbDownload.new(user: @user, source_index: 0, url: "ftp://x/y", format: "auto", status: "pending")
    assert_not dl.valid?
  end

  test "file_rel joins dir and filename" do
    dl = KbDownload.new(dir: "a/b", filename: "clip.mp4")
    assert_equal "a/b/clip.mp4", dl.file_rel
    dl.dir = ""
    assert_equal "clip.mp4", dl.file_rel
    dl.filename = nil
    assert_nil dl.file_rel
  end
end
