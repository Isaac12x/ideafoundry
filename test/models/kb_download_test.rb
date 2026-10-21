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

  test "enqueue stores explicit clip fields over the url's and labels them" do
    dl = KbDownload.enqueue(user: @user, source_index: 0, dir: "", url: "https://youtu.be/abc?t=10",
                            format: "audio", clip_start: "5:54", clip_end: "7:10")
    assert_equal [ 354, 430 ], [ dl.clip_start, dl.clip_end ]
    assert_equal "5:54–7:10", dl.clip_label
  end

  test "clip end must follow start" do
    dl = KbDownload.new(user: @user, source_index: 0, url: "https://youtu.be/abc", clip_start: 20, clip_end: 10)
    assert_not dl.valid?
  end

  test "move_subtree! follows a renamed file and its folder so the old path no longer matches" do
    dl = @user.kb_downloads.create!(url: "https://x.com/a", source_index: 0, source_path: "/k", dir: "notes", filename: "Page.pdf", status: "done")
    KbDownload.move_subtree!(user: @user, source_index: 0, old_relative_path: "notes/Page.pdf", new_source_index: 0, new_relative_path: "notes/Renamed.pdf")
    assert_equal [ dl ], @user.kb_downloads.for_file(0, "notes/Renamed.pdf").to_a
    assert_empty @user.kb_downloads.for_file(0, "notes/Page.pdf")

    KbDownload.move_subtree!(user: @user, source_index: 0, old_relative_path: "notes", new_source_index: 1, new_relative_path: "moved/deep")
    assert_equal [ dl ], @user.kb_downloads.for_file(1, "moved/deep/Renamed.pdf").to_a
  end
end
