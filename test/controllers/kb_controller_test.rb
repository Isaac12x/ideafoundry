require "test_helper"

class KbControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_f(@native_doc_path) if @native_doc_path
    FileUtils.rm_rf(@kb_dir) if @kb_dir
  end

  test "configured kb path persists and shows unavailable when folder is missing" do
    missing_path = Rails.root.join("tmp", "missing-kb-#{SecureRandom.hex(8)}").to_s

    patch settings_kb_path, params: { kb_folders: [missing_path] }

    assert_redirected_to settings_kb_path
    assert_equal [missing_path], @user.reload.kb_folders

    get kb_path

    assert_response :success
    assert_select ".kb-folder-label[title=?]", missing_path
    assert_select ".kb-folder-status", text: "(unavailable)"
    assert_equal [missing_path], @user.reload.kb_folders
  end

  test "markdown files in native kb folder are included automatically" do
    native_dir = Rails.root.join("storage", "kb")
    filename = "native-kb-#{SecureRandom.hex(8)}.md"
    @native_doc_path = native_dir.join(filename)
    FileUtils.mkdir_p(native_dir)
    File.write(@native_doc_path, "# Native KB Doc\n\nNative body")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [] }))

    get kb_path

    assert_response :success
    assert_select ".kb-folder-label", text: "App KB"
    assert_select ".kb-file-link", text: filename

    get kb_file_path(src: 0, file: filename)

    assert_response :success
    assert_includes response.body, "<h1>Native KB Doc</h1>"
    assert_includes response.body, "Native body"
  end

  test "reload reopens the last valid document instead of the first file" do
    use_isolated_kb_folder
    File.write(File.join(@kb_dir, "a-first.md"), "# First")
    File.write(File.join(@kb_dir, "z-last.md"), "# Last open")

    get kb_file_path(src: 0, file: "z-last.md")
    assert_response :success

    get kb_path

    assert_response :success
    assert_select ".kb-file-link.is-active", text: "z-last.md"
    assert_select ".kb-file-meta__name", text: "z-last.md"
    assert_includes response.body, "<h1>Last open</h1>"
  end

  test "stale last document falls back to the first available file" do
    use_isolated_kb_folder
    File.write(File.join(@kb_dir, "available.md"), "# Available")
    File.write(File.join(@kb_dir, "removed.md"), "# Removed")

    get kb_file_path(src: 0, file: "removed.md")
    File.delete(File.join(@kb_dir, "removed.md"))

    get kb_path

    assert_response :success
    assert_select ".kb-file-link.is-active", text: "available.md"
    assert_includes response.body, "<h1>Available</h1>"
  end

  test "selected files show extensions and filesystem dates in the content header" do
    use_isolated_kb_folder
    path = File.join(@kb_dir, "research-note.md")
    File.write(path, "# Dated")
    modified_at = Time.utc(2026, 7, 12, 10, 30, 0)
    File.utime(modified_at, modified_at, path)

    get kb_path(src: 0, file: "research-note.md")

    assert_response :success
    assert_select ".kb-file-link", text: "research-note.md"
    assert_select ".kb-file-meta__name", text: "research-note.md"
    assert_select ".kb-file-meta__dates dt", text: "Created"
    assert_select ".kb-file-meta__dates dt", text: "Modified"
    assert_select ".kb-file-meta__dates time[datetime]", count: 2
    rendered_modified_at = css_select(".kb-file-meta__dates > div").last.at_css("time")["datetime"]
    assert_in_delta modified_at.to_f, Time.iso8601(rendered_modified_at).to_f, 1
  end

  test "folder headers expose collapse and uncollapse all actions" do
    use_isolated_kb_folder
    FileUtils.mkdir_p(File.join(@kb_dir, "research", "sources"))
    File.write(File.join(@kb_dir, "research", "sources", "note.md"), "# Nested")

    get kb_path

    assert_response :success
    assert_select 'button[aria-label="Collapse all folders"][data-action="click->kb-folder#collapseAll"]'
    assert_select 'button[aria-label="Uncollapse all folders"][data-action="click->kb-folder#expandAll"]'
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

  test "creating a file whose name is a URL enqueues a download instead of writing a file" do
    assert_enqueued_with(job: KbDownloadJob) do
      assert_no_difference -> { Dir.glob(Rails.root.join("storage", "kb", "*")).size } do
        post kb_fs_create_path, params: {
          src: 0, dir: "", kind: "file",
          name: "https://youtu.be/dQw4w9WgXcQ", format: "audio"
        }
      end
    end

    assert_redirected_to kb_path(src: 0)
    dl = @user.kb_downloads.order(:created_at).last
    assert_equal "https://youtu.be/dQw4w9WgXcQ", dl.url
    assert_equal "audio", dl.format
  end

  test "turbo file op refreshes the tree and content in place instead of reloading" do
    use_isolated_kb_folder

    post kb_fs_create_path,
         params: { src: 0, dir: "", kind: "file", name: "turbo-note" },
         as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=kb-sidebar-tree]"
    assert_select "turbo-stream[action=update][target=kb-content]"
    assert File.exist?(File.join(@kb_dir, "turbo-note.md"))
  end

  test "turbo delete of the open file clears the content pane" do
    use_isolated_kb_folder
    File.write(File.join(@kb_dir, "doc.md"), "# doc")

    delete kb_fs_delete_path,
           params: { src: 0, path: "doc.md", sel_src: 0, sel_file: "doc.md" },
           as: :turbo_stream

    assert_response :success
    assert_not File.exist?(File.join(@kb_dir, "doc.md"))
    # Open doc was deleted → pane resets to the empty state.
    assert_select "turbo-stream[action=update][target=kb-content]" do
      assert_select "p", text: "Select a document to view"
    end
  end

  private

  # Isolated per-test KB folder as src 0, so file ops never touch the shared
  # native storage/kb dir that parallel workers race on.
  def use_isolated_kb_folder
    @kb_dir = Rails.root.join("tmp", "kb-test-#{SecureRandom.hex(8)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge(
      "kb" => { "folders" => [@kb_dir], "hide_native" => true }
    ))
  end
end
