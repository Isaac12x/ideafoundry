require "test_helper"

class KbReferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-refs-test-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "people"))
    File.write(File.join(@kb_dir, "people", "Albert Einstein.pdf"), "%PDF")
    @user.update_kb_folders([ @kb_dir ])
    @download = @user.kb_downloads.create!(
      source_index: 1, source_path: @kb_dir, dir: "people", url: "https://en.wikipedia.org/wiki/Albert_Einstein",
      format: "auto", status: "done", filename: "Albert Einstein.pdf", title: "Albert Einstein",
      references_state: "offered",
      reference_list: [
        { "url" => "https://ras.ac.uk/gold.pdf", "label" => "Gold Medal", "archive" => "https://web.archive.org/web/1/x" },
        { "url" => "https://example.org/b", "label" => "Other", "archive" => nil }
      ]
    )
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "kb page pops the reference picker as a dialog, not a tree row" do
    get kb_path
    assert_select "#kb-references-prompts dialog.kb-refs-dialog input.kb-refs__check", 2
    assert_select ".kb-refs__plan", text: /Albert Einstein-references\//
  end

  test "create moves the page into its own folder and queues chosen references beneath it" do
    assert_enqueued_jobs 1, only: KbDownloadJob do
      post kb_download_references_path(@download), params: { urls: [ "https://ras.ac.uk/gold.pdf", "https://evil.test/" ] },
           as: :turbo_stream
    end
    assert_response :success

    assert File.exist?(File.join(@kb_dir, "people", "Albert Einstein", "Albert Einstein.pdf"))
    refute File.exist?(File.join(@kb_dir, "people", "Albert Einstein.pdf"))
    assert Dir.exist?(File.join(@kb_dir, "people", "Albert Einstein", "Albert Einstein-references"))
    assert_equal "people/Albert Einstein", @download.reload.dir
    child = @user.kb_downloads.order(:id).last
    assert_equal "people/Albert Einstein/Albert Einstein-references", child.dir
    assert_equal "page", child.format
    assert_equal "skip", child.references_state
    assert_equal "https://web.archive.org/web/1/x", child.archive_url
    assert_equal "pulled", @download.reload.references_state
  end

  test "create with nothing picked queues nothing" do
    assert_no_enqueued_jobs do
      post kb_download_references_path(@download), params: {}, as: :turbo_stream
    end
    assert_equal "offered", @download.reload.references_state
  end

  test "destroy dismisses the offer and leaves the page where it was" do
    delete kb_download_references_path(@download), as: :turbo_stream
    assert_response :success
    assert_equal "dismissed", @download.reload.references_state
    assert File.exist?(File.join(@kb_dir, "people", "Albert Einstein.pdf"))
  end

  test "other users' downloads are not reachable" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", name: "Other")
    foreign = other.kb_downloads.create!(source_index: 0, url: "https://x.test/", status: "done", format: "auto")
    delete kb_download_references_path(foreign), as: :turbo_stream
    assert_response :not_found
  end
end
