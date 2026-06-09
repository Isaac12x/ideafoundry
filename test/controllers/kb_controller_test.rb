require "test_helper"

class KbControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_f(@native_doc_path) if @native_doc_path
  end

  test "configured kb path persists and shows unavailable when folder is missing" do
    missing_path = Rails.root.join("tmp", "missing-kb-#{SecureRandom.hex(8)}").to_s

    patch settings_kb_path, params: { kb_folders: [missing_path] }

    assert_redirected_to settings_kb_path
    assert_equal [missing_path], @user.reload.kb_folders

    get kb_path

    assert_response :success
    assert_select ".kb-folder-label[title=?]", missing_path
    assert_select ".kb-folder-status", text: "(unavailable - supply the new path)"
    assert_equal [missing_path], @user.reload.kb_folders
  end

  test "markdown files in native docs kb folder are included automatically" do
    native_dir = Rails.root.join("docs", "kb")
    filename = "native-kb-#{SecureRandom.hex(8)}.md"
    @native_doc_path = native_dir.join(filename)
    FileUtils.mkdir_p(native_dir)
    File.write(@native_doc_path, "# Native KB Doc\n\nNative body")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [] }))

    get kb_path

    assert_response :success
    assert_select ".kb-folder-label", text: "App KB"
    assert_select ".kb-file-link", text: "native-kb-#{filename[/native-kb-(.+)\.md/, 1]}"

    get kb_file_path(src: 0, file: filename)

    assert_response :success
    assert_includes response.body, "<h1>Native KB Doc</h1>"
    assert_includes response.body, "Native body"
  end

  test "knowledge base includes a maxims panel for high importance reminders" do
    get kb_path(tab: "maxims")

    assert_response :success
    assert_select ".kb-shell[data-tabs-default-tab-value=?]", "maxims"
    assert_select ".tab-button[data-tab-name=?]", "maxims", text: /Maxims/
    assert_select '[data-tab-panel="maxims"] .page-header h2', text: "Maxims"
    assert_select ".kb-maxims-subtitle", text: "High-importance things to remember"
    assert_select 'form[action="/maxims"]'
  end
end
