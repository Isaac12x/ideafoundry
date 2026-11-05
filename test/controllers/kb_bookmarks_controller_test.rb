require "test_helper"

class KbBookmarksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-bookmarks-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "papers"))
    File.write(File.join(@kb_dir, "papers", "study.pdf"), "%PDF")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    @user.kb_bookmarks.delete_all
    FileUtils.rm_rf(@kb_dir)
  end

  test "create, list in reading order, rename and delete" do
    post kb_bookmarks_path(src: 0, file: "papers/study.pdf"), params: { bookmark: { page: 9, label: "Late" } }, as: :json
    assert_response :created
    late = response.parsed_body["id"]
    post kb_bookmarks_path(src: 0, file: "papers/study.pdf"), params: { bookmark: { page: 2, label: "Early" } }, as: :json

    get kb_bookmarks_path(src: 0, file: "papers/study.pdf"), as: :json
    assert_equal %w[Early Late], response.parsed_body.map { |b| b["label"] }

    patch kb_bookmark_path(late), params: { bookmark: { label: "Renamed", page: 50 } }, as: :json
    assert_response :ok
    assert_equal [ "Renamed", 9 ], @user.kb_bookmarks.find(late).then { |b| [ b.label, b.page ] }

    delete kb_bookmark_path(late), as: :json
    assert_response :no_content
  end

  test "rejects bad locations and files outside the KB" do
    post kb_bookmarks_path(src: 0, file: "papers/study.pdf"), params: { bookmark: { label: "x", cfi: "nope" } }, as: :json
    assert_response :unprocessable_content
    post kb_bookmarks_path(src: 0, file: "../etc/passwd"), params: { bookmark: { label: "x", page: 1 } }, as: :json
    assert_response :not_found
  end

  test "no bookmark is created or changed while the project is locking" do
    mark = @user.kb_bookmarks.create!(source_path: File.expand_path(@kb_dir), relative_path: "papers/study.pdf", label: "p", page: 1)
    Kb::ProjectLock::STATE[File.join(File.expand_path(@kb_dir), "papers")] = { op: :lock }
    post kb_bookmarks_path(src: 0, file: "papers/study.pdf"), params: { bookmark: { label: "n", page: 2 } }, as: :json
    assert_response :conflict
    patch kb_bookmark_path(mark), params: { bookmark: { label: "z" } }, as: :json
    assert_response :conflict
    delete kb_bookmark_path(mark), as: :json
    assert_response :conflict
    assert_equal 1, @user.kb_bookmarks.where(source_path: File.expand_path(@kb_dir)).count
  ensure
    Kb::ProjectLock::STATE.clear
  end
end
