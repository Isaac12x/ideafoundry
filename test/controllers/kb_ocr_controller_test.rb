require "test_helper"

class KbOcrControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    skip "tesseract unavailable" unless Kb::ImageOcr.available?
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-ocr-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    FileUtils.cp(file_fixture("ocr_sample.png"), File.join(@kb_dir, "shot.png"))
  end

  teardown do
    @user&.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
    FileUtils.rm_rf(Kb::ImageOcr.cache_dir)
  end

  test "first request queues one job, then serves cached line boxes" do
    assert_enqueued_jobs 1, only: KbImageOcrJob do
      get kb_ocr_path(src: 0, file: "shot.png")
      get kb_ocr_path(src: 0, file: "shot.png") # lock held: no second job
    end
    assert_response :accepted

    perform_enqueued_jobs only: KbImageOcrJob
    get kb_ocr_path(src: 0, file: "shot.png")

    assert_response :success
    body = response.parsed_body
    assert_equal "done", body["status"]
    assert_equal [ "Hello selectable world", "Second line here" ], body["lines"].map { |l| l["text"] }
    assert_equal "Hello selectable world\nSecond line here", body["text"]
    assert body["lines"].all? { |l| l["x"].between?(0, 100) && l["w"].positive? }
  end

  test "private projects OCR inline and cache nothing" do
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Secret")
    FileUtils.cp(file_fixture("ocr_sample.png"), File.join(@kb_dir, "Secret", "shot.png"))
    FileUtils.rm_rf(Kb::ImageOcr.cache_dir)

    assert_no_enqueued_jobs do
      get kb_ocr_path(src: 0, file: "Secret/shot.png")
    end

    assert_equal "done", response.parsed_body["status"]
    assert_includes response.parsed_body["text"], "Hello selectable world"
    assert_empty Dir.glob(File.join(Kb::ImageOcr.cache_dir, "*"))
  end

  test "rejects non-images, traversal and missing files" do
    File.write(File.join(@kb_dir, "note.md"), "x")
    get kb_ocr_path(src: 0, file: "note.md")
    assert_response :not_found
    get kb_ocr_path(src: 0, file: "../etc/passwd")
    assert_response :not_found
    get kb_ocr_path(src: 0, file: "nope.png")
    assert_response :not_found
  end

  test "private inline OCR is memoized per process by path and mtime" do
    KbOcrController::INLINE_CACHE.clear
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Secret")
    FileUtils.cp(file_fixture("ocr_sample.png"), File.join(@kb_dir, "Secret", "shot.png"))
    runs = 0
    real = Kb::ImageOcr.method(:run!)
    Kb::ImageOcr.stub(:run!, ->(*a, **k) { runs += 1; real.call(*a, **k) }) do
      2.times { get kb_ocr_path(src: 0, file: "Secret/shot.png") }
    end
    assert_equal 1, runs
    assert_empty Dir.glob(File.join(Kb::ImageOcr.cache_dir, "*"))
  ensure
    KbOcrController::INLINE_CACHE.clear
  end
end
