require "test_helper"

# Covers rendering of non-markdown KB documents (html, docx, xlsx).
# Markdown rendering is covered by KbControllerTest and stays unchanged.
class KbMultiFormatTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup

    @kb_dir = Rails.root.join("tmp", "kb-multi-#{SecureRandom.hex(8)}").to_s
    FileUtils.mkdir_p(@kb_dir)

    @html_name = "page.html"
    File.write(File.join(@kb_dir, @html_name),
      "<!doctype html><html><body><h1>Embedded Page</h1></body></html>")

    @xlsx_name = "sheet.xlsx"
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: "Sheet1") do |sheet|
      sheet.add_row ["HelloCell", "Second"]
      sheet.add_row ["Row2A", "Row2B"]
    end
    pkg.serialize(File.join(@kb_dir, @xlsx_name))

    @docx_name = "doc.docx"
    @pandoc = system("which pandoc > /dev/null 2>&1")
    if @pandoc
      md = File.join(@kb_dir, "_src.md")
      File.write(md, "# Docx Heading\n\nDocx body paragraph.\n")
      system("pandoc", md, "-o", File.join(@kb_dir, @docx_name))
      File.delete(md)
    end

    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [@kb_dir] }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir) if @kb_dir
  end

  # Native "App KB" (storage/kb) is always listed first unless hidden;
  # our tmp folder follows it.
  def src_index
    @user.kb_hide_native? ? 0 : 1
  end

  test "html, xlsx and docx files appear in the kb tree" do
    get kb_path

    assert_response :success
    # Displayed names are extension-less, so match on the link URL.
    assert_select ".kb-file-link[href*=?]", "page.html"
    assert_select ".kb-file-link[href*=?]", "sheet.xlsx"
    assert_select ".kb-file-link[href*=?]", "doc.docx" if @pandoc
  end

  test "selecting an html file renders a sandboxed iframe pointing at the raw endpoint" do
    get kb_file_path(src: src_index, file: @html_name)

    assert_response :success
    raw = kb_raw_path(src: src_index, file: @html_name)
    assert_select "iframe.kb-embed[src=?]", raw
    sandbox = css_select("iframe.kb-embed").first["sandbox"]
    assert_not_nil sandbox, "iframe must be sandboxed"
    assert_not_includes sandbox, "allow-scripts"
    assert_not_includes sandbox, "allow-same-origin"
  end

  test "serve endpoint answers range requests with 206 partial content" do
    File.write(File.join(@kb_dir, "clip.mp4"), "0123456789")

    get kb_serve_path(src: src_index, file: "clip.mp4"), headers: { "Range" => "bytes=2-5" }

    assert_response :partial_content
    assert_equal "2345", response.body
    assert_equal "video/mp4", response.media_type
    assert_match %r{bytes 2-5/10}, response.headers["Content-Range"]
  end

  test "serve endpoint revalidates with 304 for unchanged files" do
    File.write(File.join(@kb_dir, "clip.mp4"), "0123456789")

    get kb_serve_path(src: src_index, file: "clip.mp4")
    assert_response :success
    assert_equal "0123456789", response.body
    last_modified = response.headers["Last-Modified"]
    assert last_modified.present?, "serve must send Last-Modified"

    get kb_serve_path(src: src_index, file: "clip.mp4"),
        headers: { "If-Modified-Since" => last_modified }
    assert_response :not_modified
  end

  test "raw endpoint serves html as-is with strict CSP" do
    get kb_raw_path(src: src_index, file: @html_name)

    assert_response :success
    assert_equal "text/html", response.media_type
    csp = response.headers["Content-Security-Policy"]
    assert_includes csp.to_s, "default-src 'none'"
    assert_includes response.body, "Embedded Page"
  end

  test "raw endpoint converts xlsx into an html table" do
    get kb_raw_path(src: src_index, file: @xlsx_name)

    assert_response :success
    assert_includes response.body, "<table"
    assert_includes response.body, "HelloCell"
    assert_includes response.body, "Row2B"
  end

  test "raw endpoint converts docx into html via pandoc" do
    skip "pandoc not installed" unless @pandoc

    get kb_raw_path(src: src_index, file: @docx_name)

    assert_response :success
    assert_includes response.body, "Docx Heading"
    assert_includes response.body, "Docx body paragraph"
  end

  test "raw endpoint rejects path traversal" do
    get kb_raw_path(src: src_index, file: "../../config/database.yml")

    assert_response :not_found
  end

  test "raw endpoint rejects unsupported extensions" do
    File.write(File.join(@kb_dir, "secret.rb"), "puts 1")

    get kb_raw_path(src: src_index, file: "secret.rb")

    assert_response :not_found
  end
end
