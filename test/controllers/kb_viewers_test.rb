require "test_helper"
require "zip"

class KbViewersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-viewers-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
    FileUtils.rm_rf(Kb::BookConversion.state_dir)
  end

  def write_zip(name, files)
    Zip::OutputStream.open(File.join(@kb_dir, name)) { |zip| files.each { |entry, data| zip.put_next_entry(entry); zip.write(data) } }
  end

  test "svg is served inert and gif as an image" do
    File.write(File.join(@kb_dir, "a.svg"), "<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>")
    File.binwrite(File.join(@kb_dir, "a.gif"), "GIF89a")

    get kb_serve_path(src: 0, file: "a.svg")
    assert_equal "image/svg+xml", response.media_type
    assert_includes response.headers["Content-Security-Policy"], "sandbox"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    get kb_serve_path(src: 0, file: "a.gif")
    assert_equal "image/gif", response.media_type
  end

  test "each new kind renders its viewer" do
    {
      "part.stl" => "kb-model", "part.f3d" => "kb-archive", "part.sldprt" => "Save As STEP",
      "pack.zip" => "kb-archive", "book.epub" => "kb-book", "book.mobi" => "Convert to read", "issue.cbz" => "kb-archive",
      "anim.gif" => "kb-image-preview", "logo.svg" => "kb-image-preview--vector"
    }.each do |name, marker|
      File.binwrite(File.join(@kb_dir, name), "x")
      get kb_file_path(src: 0, file: name)
      assert_response :success, name
      assert_includes response.body, marker, name
    end
  end

  test "archive frame lists contents as a folder tree" do
    write_zip("pack.zip", "docs/a.txt" => "hello", "img/p.png" => "png")
    get kb_archive_path(src: 0, file: "pack.zip")
    assert_response :success
    assert_includes response.body, "2 files"
    assert_includes response.body, "docs"
    assert_includes response.body, "Preview"
  end

  test "archive entries stream images inline and everything else as attachment" do
    write_zip("pack.zip", "docs/a.txt" => "hello", "img/p.png" => "png", "x.svg" => "<svg/>")

    get kb_archive_entry_path(src: 0, file: "pack.zip", entry: "img/p.png")
    assert_equal "image/png", response.media_type
    assert_match(/inline/, response.headers["Content-Disposition"])

    get kb_archive_entry_path(src: 0, file: "pack.zip", entry: "docs/a.txt")
    assert_equal "application/octet-stream", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])

    get kb_archive_entry_path(src: 0, file: "pack.zip", entry: "x.svg")
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_includes response.headers["Content-Security-Policy"], "sandbox"
  end

  test "archive entries refuse names that are not in the listing" do
    write_zip("pack.zip", "a.txt" => "hello")
    get kb_archive_entry_path(src: 0, file: "pack.zip", entry: "../../etc/passwd")
    assert_response :not_found
    get kb_archive_entry_path(src: 0, file: "../pack.zip", entry: "a.txt")
    assert_response :not_found
  end

  test "comic frame carries natural-ordered page urls" do
    write_zip("c.cbz", "p10.jpg" => "a", "p2.jpg" => "b")
    get kb_archive_path(src: 0, file: "c.cbz")
    assert_response :success
    assert_operator response.body.index("p2.jpg"), :<, response.body.index("p10.jpg")
  end

  test "f3d shows the embedded preview image and an honest note" do
    write_zip("part.f3d", "Manifest.dat" => "m", "FusionAssetName/Thumbnails/preview.png" => "png")
    get kb_archive_path(src: 0, file: "part.f3d")
    assert_response :success
    assert_includes response.body, "Preview image stored inside the file"
    assert_includes response.body, "preview.png"
  end

  test "book without a converter reports the install hint and still offers no conversion" do
    File.write(File.join(@kb_dir, "b.mobi"), "x")
    Kb::LocalTool.stub(:path, nil) do
      File.stub(:executable?, false) do
        get kb_book_path(src: 0, file: "b.mobi")
        assert_equal "missing_tool", response.parsed_body["status"]
        assert_includes response.parsed_body["hint"], "brew install --cask calibre"

        post kb_book_path(src: 0, file: "b.mobi")
        assert_response :unprocessable_content
      end
    end
  end

  test "convert queues one job and a ready sidecar is served by url" do
    File.write(File.join(@kb_dir, "b.mobi"), "x")
    Kb::BookConversion.stub(:tool, "/bin/true") do
      assert_enqueued_jobs 1, only: KbBookConvertJob do
        post kb_book_path(src: 0, file: "b.mobi")
        post kb_book_path(src: 0, file: "b.mobi")
      end
      assert_response :accepted
      assert_equal "running", response.parsed_body["status"]
    end
    FileUtils.rm_f(Kb::BookConversion.state_file(File.join(@kb_dir, "b.mobi"), "lock"))

    File.write(File.join(@kb_dir, ".b.mobi.epub"), "epub")
    get kb_book_path(src: 0, file: "b.mobi")
    assert_equal "ready", response.parsed_body["status"]
    get response.parsed_body["url"]
    assert_response :success
  end

  test "non-book files are not convertible" do
    File.write(File.join(@kb_dir, "n.md"), "x")
    get kb_book_path(src: 0, file: "n.md")
    assert_response :not_found
  end
end
