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

  test "waits while the target project is locking and fails when it is locked" do
    original = @user.settings.deep_dup
    base = File.expand_path(Dir.mktmpdir)
    project = Kb::Project.create!(base: base, parent_rel: "", name: "Vault")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ base ], "hide_native" => true }))
    dl = @user.kb_downloads.create!(source_index: 0, source_path: base, dir: "Vault", url: "https://x.com/f.pdf", format: "auto", status: "pending")

    Kb::ProjectLock::STATE[project.abs] = { op: :lock }
    assert_enqueued_with(job: KbDownloadJob) { KbDownloadJob.perform_now(dl.id) }
    assert_equal "pending", dl.reload.status

    Kb::ProjectLock::STATE.clear
    Kb::ProjectLock.write_stub(project.abs, { "private" => true, "locked" => true, "archive" => "Vault.7z" })
    KbDownloadJob.perform_now(dl.id)
    assert_equal "failed", dl.reload.status
    assert_match(/locked/i, dl.error)
  ensure
    Kb::ProjectLock::STATE.clear
    @user.update!(settings: original)
    FileUtils.rm_rf(base)
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

class KbDownloadJobClipArgsTest < ActiveSupport::TestCase
  def args(clip_start:, clip_end:, format: "video")
    dl = KbDownload.new(url: "https://www.youtube.com/watch?v=ews_k4ikjuy", format: format, clip_start: clip_start, clip_end: clip_end)
    KbDownloadJob.yt_dlp_args("yt-dlp", dl, "/tmp/d")
  end

  test "start and end become a keyframe-cut section named in the file" do
    a = args(clip_start: 354, clip_end: 430)
    assert_equal [ "--download-sections", "*354-430", "--force-keyframes-at-cuts" ], a.each_cons(3).find { |x, *| x == "--download-sections" }
    assert_includes a, "%(title)s [clip 5m54s-7m10s].%(ext)s"
    assert_equal "https://www.youtube.com/watch?v=ews_k4ikjuy", a.last
  end

  test "start only runs to the end; audio keeps the mp3 preset" do
    a = args(clip_start: 354, clip_end: nil, format: "audio")
    assert_includes a, "*354-inf"
    assert_includes a, "%(title)s [clip from 5m54s].%(ext)s"
    assert_equal [ "-t", "mp3" ], a.each_cons(2).find { |x, _| x == "-t" }
  end

  test "no clip leaves the plain argv" do
    a = args(clip_start: nil, clip_end: nil)
    refute_includes a, "--download-sections"
    assert_includes a, "%(title)s.%(ext)s"
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
    KbDownloadJob.singleton_class.alias_method :real_video_kind, :video_kind
    KbDownloadJob.define_singleton_method(:video_kind) { |_url| nil } # no yt-dlp probe / network
    FileUtils.mkdir_p(@kb_dir)
    @user.update_kb_folders([ @kb_dir ])
    @article = "<html><head><title>Einstein</title></head><body><article>" \
               "<p>#{'Physics. ' * 300}</p><ol class='references'><li><a href='https://ref.test/a'>A</a></li></ol>" \
               "</article></body></html>"
  end

  teardown do
    KbDownloadJob.singleton_class.alias_method :video_kind, :real_video_kind
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

  test "auto: a page yt-dlp has an extractor for is downloaded as video, not a PDF" do
    dl = enqueue("https://www.ted.com/talks/some_talk")
    job = KbDownloadJob.new
    job.define_singleton_method(:yt_dlp) { |_dl, d, _kind = nil| File.join(d, "talk.mp4").tap { |f| File.write(f, "x") } }
    KbDownloadJob.stub(:video_kind, :video) do
      Kb::WebPage.stub(:fetch, ->(_) { flunk "article path must not run" }) { job.perform(dl.id) }
    end

    assert_equal [ "done", "talk.mp4", "pending" ], dl.reload.then { |d| [ d.status, d.filename, d.transcript_status ] }
  end

  test "auto: a page with no video extractor still becomes a reader PDF" do
    dl = enqueue("https://en.wikipedia.org/wiki/Einstein")
    page = Kb::WebPage.new(@article, dl.url)
    Kb::WebPage.stub(:fetch, page) do
      Kb::ReaderPdf.stub(:write, ->(_h, dest) { File.write(dest, "%PDF"); true }) { KbDownloadJob.perform_now(dl.id) }
    end

    assert_equal "Einstein.pdf", dl.reload.filename
  end

  test "vimeo page URLs use the embed player" do
    assert_equal "https://player.vimeo.com/video/76979871", KbDownloadJob.media_url("https://vimeo.com/76979871")
    assert_equal "https://player.vimeo.com/video/1?h=abc123", KbDownloadJob.media_url("https://vimeo.com/1/abc123")
    assert_equal "https://example.com/v", KbDownloadJob.media_url("https://example.com/v")
  end
end

class KbDownloadJobDirectClipTest < ActiveJob::TestCase
  setup do
    skip "ffmpeg unavailable" unless system("ffmpeg -version", out: File::NULL, err: File::NULL)
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @dir = Rails.root.join("tmp", "kb-clip-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@dir)
    @path = File.join(@dir, "talk.mp4")
    system("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=duration=6:size=64x64:rate=10",
           "-f", "lavfi", "-i", "sine=duration=6", "-c:v", "libx264", "-c:a", "aac", "-shortest", @path, exception: true)
  end

  teardown { FileUtils.rm_rf(@dir) if @dir }

  def duration(path) = Kb::MediaInspector.new(path).call[:duration].to_f

  test "direct media with start and end is cut to that range and the whole file is dropped" do
    dl = @user.kb_downloads.create!(source_index: 0, dir: "", url: "https://example.com/talk.mp4#t=1,3", status: "running")
    job = KbDownloadJob.new
    out = job.send(:cut_clip, dl, @path)

    assert_equal File.join(@dir, "talk [clip 1s-3s].mp4"), out
    assert_in_delta 2.0, duration(out), 0.3
    assert_not File.exist?(@path)
    assert job.instance_variable_get(:@clipped)
  end

  test "start-only clip runs to the end and is named from" do
    dl = @user.kb_downloads.create!(source_index: 0, dir: "", url: "https://example.com/talk.mp4?t=4", status: "running")
    out = KbDownloadJob.new.send(:cut_clip, dl, @path)

    assert_equal "talk [clip from 4s].mp4", File.basename(out)
    assert_in_delta 2.0, duration(out), 0.3
  end

  test "a failed cut fails the download and keeps the file" do
    File.binwrite(@path, "not media")
    dl = @user.kb_downloads.create!(source_index: 0, dir: "", url: "https://example.com/talk.mp4#t=1,3", status: "running")

    assert_nil KbDownloadJob.new.send(:cut_clip, dl, @path)
    assert_equal "failed", dl.reload.status
    assert_match(/Could not cut the clip/, dl.error)
    assert File.exist?(@path)
  end
end
