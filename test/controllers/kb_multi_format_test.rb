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

  # Native "App KB" (docs/kb) is listed first when it has markdown; our tmp folder follows.
  def src_index
    native = Dir.exist?(KbController::NATIVE_KB_PATH) &&
             Dir.glob(File.join(KbController::NATIVE_KB_PATH, "**", "*.md")).any?
    native ? 1 : 0
  end

  test "html, xlsx and docx files appear in the kb tree" do
    get kb_path

    assert_response :success
    assert_select ".kb-file-link", text: /page\.html/
    assert_select ".kb-file-link", text: /sheet\.xlsx/
    assert_select ".kb-file-link", text: /doc\.docx/ if @pandoc
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
