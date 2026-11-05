require "test_helper"

class KbMediaEditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-media-controller-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "no media edits into a project that is locking" do
    FileUtils.mkdir_p(File.join(@kb_dir, "Proj"))
    File.binwrite(File.join(@kb_dir, "Proj", "pic.png"), "image-bytes")
    Kb::ProjectLock::STATE[File.join(File.realpath(@kb_dir), "Proj")] = { op: :lock }
    Kb::ProjectLock::STATE[File.join(@kb_dir, "Proj")] = { op: :lock }
    assert_no_difference -> { KbMediaEdit.count } do
      post kb_media_edits_path, params: { src: 0, file: "Proj/pic.png", operations: { brightness: "1.1" } }
    end
    assert_response :conflict
  ensure
    Kb::ProjectLock::STATE.clear
  end

  test "view mode only exposes an edit button and loads the image studio on click route" do
    File.binwrite(File.join(@kb_dir, "evidence.png"), "image-bytes")

    get kb_file_path(src: 0, file: "evidence.png")
    assert_response :success
    assert_select "a.kb-content-edit-link[href=?]", kb_edit_path(src: 0, file: "evidence.png"), text: /Edit/
    assert_select ".kb-media-editor", count: 0

    get kb_edit_path(src: 0, file: "evidence.png")
    assert_response :success
    assert_select 'form.kb-media-editor[data-controller="kb-media-editor"]'
    assert_select 'canvas[data-kb-media-editor-target="canvas"]'
    assert_select 'button[data-kb-media-editor-mode-param="crop"]', text: "Crop"
    assert_select 'input[name="operations[brightness]"]'
  end

  test "video and audio files receive format-specific full editors" do
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "video-bytes")
    File.binwrite(File.join(@kb_dir, "interview.mp3"), "audio-bytes")

    get kb_edit_path(src: 0, file: "clip.mp4")
    assert_response :success
    assert_select "video[data-kb-media-editor-target=media]"
    assert_select 'input[name="operations[trim_start]"]'
    assert_select 'select[name="operations[crop_aspect]"]'
    assert_select 'input[name="operations[mute]"]'
    assert_select 'input[name="operations[brightness]"]'

    get kb_edit_path(src: 0, file: "interview.mp3")
    assert_response :success
    assert_select "audio[data-kb-media-editor-target=media]"
    assert_select "canvas.kb-media-editor__waveform"
    assert_select 'input[name="operations[normalize]"]'
    assert_select 'input[name="operations[mono]"]'
  end

  test "pdf html and opaque files all have an edit experience" do
    File.binwrite(File.join(@kb_dir, "paper.pdf"), "%PDF-1.4")
    File.write(File.join(@kb_dir, "source.html"), "<h1>Evidence</h1>")
    File.binwrite(File.join(@kb_dir, "model.blend"), "opaque")

    get kb_edit_path(src: 0, file: "paper.pdf")
    assert_response :success
    assert_select 'input[name="operations[page_sequence]"]'
    assert_select 'select[name="operations[pdf_rotation]"]'

    get kb_edit_path(src: 0, file: "source.html")
    assert_response :success
    assert_select "textarea[name=source_content]", text: /Evidence/

    get kb_edit_path(src: 0, file: "model.blend")
    assert_response :success
    assert_select "input[type=file][name=replacement_file]"
  end

  test "queues a local video render with a constrained edit recipe" do
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "video-bytes")

    assert_enqueued_with(job: KbMediaEditRunnerJob) do
      post kb_media_edits_path,
           params: {
             src: 0,
             file: "clip.mp4",
             operations: { trim_start: "1.5", trim_end: "8", speed: "1.25", crop_aspect: "16:9", unexpected: "drop-me" }
           },
           as: :json
    end

    assert_response :accepted
    edit = @user.kb_media_edits.last
    assert_equal "pending", edit.status
    assert_equal "video", edit.media_kind
    assert_equal "1.5", edit.operations["trim_start"]
    assert_equal "16:9", edit.operations["crop_aspect"]
    assert_not edit.operations.key?("unexpected")
    assert_equal kb_media_edit_path(edit), response.parsed_body["status_url"]
  end

  test "image edits require rendered bytes and reject traversal" do
    File.binwrite(File.join(@kb_dir, "evidence.png"), "image-bytes")

    post kb_media_edits_path, params: { src: 0, file: "evidence.png" }, as: :json
    assert_response :unprocessable_content

    upload = Rack::Test::UploadedFile.new(StringIO.new("edited-image"), "image/png", original_filename: "evidence.png")
    post kb_media_edits_path, params: {
           src: 0,
           file: "evidence.png",
           rendered_file: upload,
           operations: { client_recipe: '[{"tool":"crop","x":2,"y":3,"width":10,"height":8}]' }
         },
         headers: { "Accept" => "application/json" }
    assert_response :accepted
    edit = @user.kb_media_edits.last
    assert edit.replacement_file.attached?
    assert_includes edit.operations["client_recipe"], '"tool":"crop"'

    post kb_media_edits_path, params: { src: 0, file: "../../etc/passwd" }, as: :json
    assert_response :unprocessable_content
  end

  test "html source edits queue as local replacement bytes" do
    File.write(File.join(@kb_dir, "source.html"), "<h1>Before</h1>")

    assert_enqueued_with(job: KbMediaEditRunnerJob) do
      post kb_media_edits_path,
           params: { src: 0, file: "source.html", source_content: "<h1>After</h1>" },
           as: :json
    end

    assert_response :accepted
    edit = @user.kb_media_edits.last
    assert_equal "embed", edit.media_kind
    assert edit.replacement_file.attached?
    assert_equal "<h1>After</h1>", edit.replacement_file.download
  end

  test "does not queue concurrent edits for the same vault path" do
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "video-bytes")
    @user.kb_media_edits.create!(
      source_index: 0,
      source_path: @kb_dir,
      relative_path: "clip.mp4",
      media_kind: "video",
      operations: {},
      status: "running"
    )

    post kb_media_edits_path, params: { src: 0, file: "clip.mp4", operations: {} }, as: :json

    assert_response :conflict
    assert_equal 1, @user.kb_media_edits.where(relative_path: "clip.mp4").count
  end

  test "status returns the copy path explicitly, not the source" do
    edit = @user.kb_media_edits.create!(source_index: 0, source_path: @kb_dir, relative_path: "clip.mp4", media_kind: "video",
                                        operations: {}, status: "done", result_relative_path: "clip (edited).mp4")

    get kb_media_edit_path(edit), as: :json

    body = response.parsed_body
    assert_equal "clip (edited).mp4", body["result_path"]
    assert_includes body["file_url"], CGI.escape("clip (edited).mp4")
  end

  test "screenshot saves an exact-frame png beside the video" do
    skip "ffmpeg unavailable" unless system("ffmpeg -version", out: File::NULL, err: File::NULL)
    video = File.join(@kb_dir, "clip.mp4")
    system("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=duration=2:size=64x64:rate=10",
           "-c:v", "libx264", video, exception: true)

    post kb_screenshot_path, params: { src: 0, file: "clip.mp4", time: "1.5" }, as: :json

    assert_response :created
    body = response.parsed_body
    assert_equal "clip \u2014 00m01s.png", body["name"]
    assert_equal "\x89PNG".b, File.binread(File.join(@kb_dir, body["file"]), 4)

    post kb_screenshot_path, params: { src: 0, file: "clip.mp4", time: "1.5" }, as: :json
    assert_equal "clip \u2014 00m01s 2.png", response.parsed_body["name"]
  end

  test "screenshot rejects non-video files and bad timestamps" do
    File.binwrite(File.join(@kb_dir, "evidence.png"), "x")
    File.binwrite(File.join(@kb_dir, "clip.mp4"), "x")

    post kb_screenshot_path, params: { src: 0, file: "evidence.png", time: "1" }, as: :json
    assert_response :unprocessable_content
    post kb_screenshot_path, params: { src: 0, file: "clip.mp4", time: "-3" }, as: :json
    assert_response :unprocessable_content
  end

  test "edited images are served under a version param that changes with the file" do
    path = File.join(@kb_dir, "evidence.png")
    File.binwrite(path, "one")
    get kb_file_path(src: 0, file: "evidence.png")
    first = css_select("img.kb-image-preview").first["src"]
    File.binwrite(path, "two")
    File.utime(Time.now + 5, Time.now + 5, path)

    get kb_file_path(src: 0, file: "evidence.png")
    second = css_select("img.kb-image-preview").first["src"]

    assert_match(/[?&]v=\d+/, first)
    refute_equal first, second
  end
end
