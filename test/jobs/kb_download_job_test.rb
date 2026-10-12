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

class KbDownloadJobYoutubeTest < ActiveJob::TestCase
  def run_download(url, file)
    user = User.first || User.create!(email: "test@example.com", name: "Test")
    dir = Rails.root.join("tmp", "kb-yt-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(dir)
    settings = user.settings.deep_dup
    user.update_kb_folders([ dir ])
    dl = user.kb_downloads.create!(source_index: 1, source_path: dir, dir: "", url: url, format: "auto", status: "pending")
    job = KbDownloadJob.new
    save = ->(_dl, d) { File.join(d, file).tap { |f| File.write(f, "x") } }
    job.define_singleton_method(:yt_dlp, &save)
    job.define_singleton_method(:http_download, &save)
    yield dl, job
    dl.reload
  ensure
    user&.update!(settings: settings)
    FileUtils.rm_rf(dir)
  end

  test "finished youtube download queues its transcript" do
    dl = run_download("https://youtu.be/abc", "v.mp4") do |d, job|
      assert_enqueued_with(job: KbTranscriptJob, args: [ d.id ]) { job.perform(d.id) }
    end
    assert_equal [ "done", "pending" ], [ dl.status, dl.transcript_status ]
  end

  test "video from another site queues its transcript" do
    dl = run_download("https://vimeo.com/123", "clip.mp4") do |d, job|
      assert_enqueued_with(job: KbTranscriptJob, args: [ d.id ]) { job.perform(d.id) }
    end
    assert_equal "pending", dl.transcript_status
  end

  test "direct video file waits for audio without fetching captions" do
    dl = run_download("https://example.com/talk.mp4", "talk.mp4") do |d, job|
      assert_no_enqueued_jobs { job.perform(d.id) }
    end
    assert_equal "awaiting_audio", dl.transcript_status
  end

  test "non-video download has no transcript" do
    dl = run_download("https://example.com/a.pdf", "a.pdf") { |d, job| job.perform(d.id) }
    assert_nil dl.transcript_status
  end
end

class KbDownloadJobReaderTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-reader-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update_kb_folders([ @kb_dir ])
    @article = "<html><head><title>Einstein</title></head><body><article>" \
               "<p>#{'Physics. ' * 300}</p><ol class='references'><li><a href='https://ref.test/a'>A</a></li></ol>" \
               "</article></body></html>"
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  def enqueue(url, **extra)
    @user.kb_downloads.create!(source_index: 1, source_path: @kb_dir, dir: "", url: url,
                               format: "auto", status: "pending", **extra)
  end

  test "saves an article as a reader PDF and offers its references" do
    dl = enqueue("https://en.wikipedia.org/wiki/Einstein")
    page = Kb::WebPage.new(@article, dl.url)
    write = ->(_html, dest) { File.write(dest, "%PDF"); true }

    Kb::WebPage.stub(:fetch, page) do
      Kb::ReaderPdf.stub(:write, write) { KbDownloadJob.perform_now(dl.id) }
    end

    dl.reload
    assert_equal "done", dl.status
    assert_equal "Einstein.pdf", dl.filename
    assert File.exist?(File.join(@kb_dir, "Einstein.pdf"))
    assert_equal "offered", dl.references_state
    assert_equal [ "https://ref.test/a" ], dl.reference_list.map { |r| r["url"] }
  end

  test "reference pulls never offer their own references" do
    dl = enqueue("https://ref.test/a", references_state: "skip")
    page = Kb::WebPage.new(@article, dl.url)

    Kb::WebPage.stub(:fetch, page) do
      Kb::ReaderPdf.stub(:write, ->(_h, dest) { File.write(dest, "%PDF"); true }) { KbDownloadJob.perform_now(dl.id) }
    end

    assert_equal "skip", dl.reload.references_state
  end

  test "paywalled page with no archive yet asks for one and retries later" do
    dl = enqueue("https://news.test/story")
    blocked = Kb::WebPage.new("", dl.url, blocked: true)
    asked = []

    Kb::WebPage.stub(:fetch, blocked) do
      Kb::WebPage.stub(:archive_candidates, []) do
        Kb::WebPage.stub(:request_archive, ->(url) { asked << url }) do
          assert_enqueued_with(job: KbDownloadJob) { KbDownloadJob.perform_now(dl.id) }
        end
      end
    end

    dl.reload
    assert_equal "pending", dl.status
    assert_equal 1, dl.attempts
    assert_equal [ dl.url ], asked
  end

  test "paywalled page is read from an archived copy" do
    dl = enqueue("https://news.test/story", archive_url: "https://web.archive.org/web/1id_/https://news.test/story")
    blocked = Kb::WebPage.new("", dl.url, blocked: true)
    archived = Kb::WebPage.new(@article, dl.archive_url)
    fetch = ->(url) { url == dl.url ? blocked : archived }
    html_seen = nil

    Kb::WebPage.stub(:fetch, fetch) do
      Kb::ReaderPdf.stub(:write, ->(html, dest) { html_seen = html; File.write(dest, "%PDF"); true }) do
        KbDownloadJob.perform_now(dl.id)
      end
    end

    assert_equal "done", dl.reload.status
    assert_includes html_seen, "via web.archive.org"
  end

  test "gives up after the archive retries run out" do
    dl = enqueue("https://news.test/story", attempts: KbDownloadJob::ARCHIVE_RETRIES)

    Kb::WebPage.stub(:fetch, Kb::WebPage.new("", "https://news.test/story", blocked: true)) do
      Kb::WebPage.stub(:archive_candidates, []) { KbDownloadJob.perform_now(dl.id) }
    end

    assert_equal "failed", dl.reload.status
    assert_match(/Paywalled/, dl.error)
  end
end
