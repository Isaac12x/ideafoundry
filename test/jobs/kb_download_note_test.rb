require "test_helper"

class KbDownloadNoteTest < ActiveJob::TestCase
  test "finished download writes its note as the .note.md sidecar" do
    user = User.first || User.create!(email: "test@example.com", name: "Test")
    dir = Rails.root.join("tmp", "kb-dl-note-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(dir)
    settings = user.settings.deep_dup
    user.update_kb_folders([ dir ])
    dl = user.kb_downloads.create!(source_index: 1, source_path: dir, dir: "", url: "https://vimeo.com/123", format: "auto",
                                   status: "pending", note: "the pacing is the reason")
    job = KbDownloadJob.new
    job.define_singleton_method(:yt_dlp) { |_dl, d| File.join(d, "v.mp4").tap { |f| File.write(f, "x") } }
    job.perform(dl.id)

    assert_equal "the pacing is the reason\n", File.read(File.join(dir, "v.mp4.note.md"))
    assert_nil dl.reload.note
    assert_equal "done", dl.status
  ensure
    user&.update!(settings: settings)
    FileUtils.rm_rf(dir)
  end
end

class KbDownloadSourceTest < ActiveJob::TestCase
  test "finished download keeps its link and the yt-dlp description in a sidecar" do
    user = User.first || User.create!(email: "test@example.com", name: "Test")
    dir = Rails.root.join("tmp", "kb-dl-src-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(dir)
    settings = user.settings.deep_dup
    user.update_kb_folders([ dir ])
    dl = user.kb_downloads.create!(source_index: 1, source_path: dir, dir: "", url: "https://vimeo.com/123", format: "auto", status: "pending")
    job = KbDownloadJob.new
    job.define_singleton_method(:yt_dlp) do |_dl, d|
      File.write(File.join(d, "v.description"), "watch https://x.com")
      @from_yt_dlp = true
      File.join(d, "v.mp4").tap { |f| File.write(f, "x") }
    end
    job.perform(dl.id)

    assert_equal({ "url" => "https://vimeo.com/123", "description" => "watch https://x.com" }, Kb::Source.read(File.join(dir, "v.mp4")))
    assert_not File.exist?(File.join(dir, "v.description"))
  ensure
    user&.update!(settings: settings)
    FileUtils.rm_rf(dir)
  end
end
