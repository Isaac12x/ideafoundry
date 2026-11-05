require "test_helper"

class KbControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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

    patch settings_kb_path, params: { kb_folders: [ missing_path ] }

    assert_redirected_to settings_kb_path
    assert_equal [ missing_path ], @user.reload.kb_folders

    get kb_path

    assert_response :success
    assert_select ".kb-folder-label[title=?]", missing_path
    assert_select ".kb-folder-status", text: "(unavailable)"
    assert_equal [ missing_path ], @user.reload.kb_folders
  end

  test "markdown files in native kb folder are included automatically" do
    native_dir = KbSource::NATIVE_PATH
    filename = "native-kb-#{SecureRandom.hex(8)}.md"
    @native_doc_path = File.join(native_dir, filename)
    FileUtils.mkdir_p(native_dir)
    File.write(@native_doc_path, "# Native KB Doc\n\nNative body")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [] }))

    get kb_path

    assert_response :success
    assert_select ".kb-folder-header", 0 # single root: no root row
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

  test "viewer shows the download link and description from the sidecar, or the row url for older downloads" do
    use_isolated_kb_folder
    File.binwrite(File.join(@kb_dir, "v.mp4"), "x")
    Kb::Source.write!(File.join(@kb_dir, "v.mp4"), url: "https://example.com/watch?v=1", description: "<b>hi</b> https://a.com")
    @user.kb_downloads.create!(source_index: 0, source_path: @kb_dir, dir: "", url: "https://old.example/x", status: "done", filename: "old.mp4")
    File.binwrite(File.join(@kb_dir, "old.mp4"), "x")

    get kb_path(src: 0, file: "v.mp4")
    assert_select "a.kb-file-meta__source[href=?][rel=?]", "https://example.com/watch?v=1", "noopener noreferrer"
    assert_select ".kb-description__body a[href=?]", "https://a.com"
    assert_select ".kb-description__body b", count: 0

    get kb_path(src: 0, file: "old.mp4")
    assert_select "a.kb-file-meta__source[href=?]", "https://old.example/x"
    assert_select ".kb-description", count: 0
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

  test "single root puts collapse, uncollapse and new in the toolbar, with no root row" do
    use_isolated_kb_folder
    FileUtils.mkdir_p(File.join(@kb_dir, "research", "sources"))
    File.write(File.join(@kb_dir, "research", "sources", "note.md"), "# Nested")

    get kb_path

    assert_response :success
    assert_select ".kb-tree-head" do
      assert_select 'button[aria-label="Collapse all folders"][data-action="kb-tree#collapseAll"]'
      assert_select 'button[aria-label="Uncollapse all folders"][data-action="kb-tree#expandAll"]'
      assert_select 'button[aria-label="New file or folder"][data-kb-tree-type-param=root]'
    end
    assert_select ".kb-folder-header", 0
    assert_select ".kb-tree--solo[data-kb-tree-type-param=root][data-action*='drop->kb-tree#drop']"
  end

  test "several roots keep a labelled row each and no toolbar root actions" do
    use_isolated_kb_folder
    second = Rails.root.join("tmp", "kb-second-#{SecureRandom.hex(4)}").to_s
    FileUtils.mkdir_p(second)
    @user.update!(settings: @user.settings.deep_merge("kb" => { "folders" => [ @kb_dir, second ] }))

    get kb_path

    assert_select ".kb-folder-header", 2
    assert_select ".kb-tree-head button[aria-label='New file or folder']", 0
  ensure
    FileUtils.rm_rf(second) if second
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
      assert_no_difference -> { Dir.glob(File.join(KbSource::NATIVE_PATH, "*")).size } do
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

  test "ChatGPT and Claude URLs queue a capture job instead of a download" do
    use_isolated_kb_folder
    FileUtils.mkdir_p(File.join(@kb_dir, "chats"))
    { "https://chatgpt.com/c/abc" => "chats", "https://claude.ai/chat/xyz" => "" }.each do |url, dir|
      assert_no_difference -> { KbDownload.count } do
        assert_difference -> { @user.capture_jobs.count }, 1 do
          post kb_fs_create_path, params: { src: 0, dir: dir, kind: "file", name: url }
        end
      end
      job = @user.capture_jobs.order(:id).last
      assert_equal [ url, "md", 0, dir ], [ job.url, job.file_format, job.source_index, job.dir ]
      assert_match(/browser extension/, flash[:notice])
    end
  end

  test "ordinary URLs still create a download, not a capture job" do
    assert_no_difference -> { CaptureJob.count } do
      assert_difference -> { KbDownload.count }, 1 do
        post kb_fs_create_path, params: { src: 0, dir: "", kind: "file", name: "https://example.com/a.pdf" }
      end
    end
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

  test "basics tab renders the periodic table instrument" do
    get kb_path(tab: "basics")

    assert_response :success
    assert_select 'button.tab-button[data-tab-name="basics"]'
    assert_select '[data-tab-panel="basics"] section.ptable[data-controller~="periodic-table"]'
    assert_select "script[type=importmap]", text: %r{lib/periodic_table/elements}
  end

  test "basics tab renders the chemistry bench with every instrument" do
    get kb_path(tab: "basics")

    assert_select 'section.ptable section.ptable-bench[data-controller~="periodic-bench"]'
    %w[combine formula equation alloy compare plot nuclides map guide].each do |tab|
      assert_select %([role="tab"][data-tab="#{tab}"])
      assert_select %([role="tabpanel"][data-panel="#{tab}"])
    end
    %w[chem compounds element_details nuclides world bench_chem bench_views bench_nuclides bench_map bench_guide].each do |mod|
      assert_select "script[type=importmap]", text: %r{lib/periodic_table/#{mod}}
    end
  end

  test "finished download shows a new dot until its file is opened" do
    use_isolated_kb_folder
    FileUtils.mkdir_p(File.join(@kb_dir, "docs"))
    File.write(File.join(@kb_dir, "docs", "fresh.md"), "# Fresh")
    File.write(File.join(@kb_dir, "old.md"), "# Old")
    base = { user: @user, source_index: 0, url: "https://example.com/x", status: "done", source_path: File.expand_path(@kb_dir) }
    fresh = KbDownload.create!(base.merge(dir: "docs", filename: "fresh.md"))
    KbDownload.create!(base.merge(filename: "old.md", opened_at: 1.day.ago))

    get kb_path
    assert_select ".kb-file-row.is-new", count: 1
    assert_select ".kb-file-row.is-new .kb-file-link", text: "fresh.md"
    assert_select ".kb-dir-header .kb-new-dot--dir", count: 1

    get kb_file_path(src: 0, file: "docs/fresh.md")
    assert_response :success
    assert_not_nil fresh.reload.opened_at

    get kb_path
    assert_select ".kb-new-dot", count: 0
  end

  test "opening a new download tells the open tabs from a job, never by rebuilding the tree inside the request" do
    use_isolated_kb_folder
    File.write(File.join(@kb_dir, "fresh.md"), "# Fresh")
    KbDownload.create!(user: @user, source_index: 0, url: "https://example.com/x", status: "done", source_path: File.expand_path(@kb_dir), dir: "", filename: "fresh.md")

    built = 0
    Kb::TreeBuilder.stub(:build, ->(*) { built += 1; [] }) do
      assert_enqueued_with(job: KbTreeSeenJob, args: [ @user.id, 0, "fresh.md" ]) do
        get kb_file_path(src: 0, file: "fresh.md"), headers: { "Turbo-Frame" => "kb-content" }
      end
    end
    assert_equal 0, built, "the tree was rebuilt inside the file request"
  end

  test "full file GET renders the KB shell, frame request only the document" do
    use_isolated_kb_folder
    File.write(File.join(@kb_dir, "doc.md"), "# Deep Link")

    get kb_file_path(src: 0, file: "doc.md")
    assert_select "body.kb-page"
    assert_select ".kb-shell .kb-file-link", text: "doc.md"
    assert_includes response.body, "<h1>Deep Link</h1>"

    get kb_file_path(src: 0, file: "doc.md"), headers: { "Turbo-Frame" => "kb-content" }
    assert_includes response.body, "<h1>Deep Link</h1>"
    assert_select ".kb-shell", 0
    assert_select "body.kb-page", 0
  end

  test "sort persists a whitelisted mode and rejects others" do
    patch kb_sort_path(mode: "date_desc"), as: :turbo_stream

    assert_response :success
    assert_equal "date_desc", @user.reload.settings.dig("kb", "sort")

    patch kb_sort_path(mode: "bogus"), as: :turbo_stream

    assert_equal "date_desc", @user.reload.settings.dig("kb", "sort")
  end

  private

  # Isolated per-test KB folder as src 0, so file ops never touch the shared
  # native storage/kb dir that parallel workers race on.
  def use_isolated_kb_folder
    @kb_dir = Rails.root.join("tmp", "kb-test-#{SecureRandom.hex(8)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge(
      "kb" => { "folders" => [ @kb_dir ], "hide_native" => true }
    ))
  end
end
