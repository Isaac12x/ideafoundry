require "test_helper"

class KbAnnotationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-annotations-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "papers"))
    File.write(File.join(@kb_dir, "papers", "study.pdf"), "%PDF")
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [@kb_dir], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    @user.kb_annotations.delete_all
    FileUtils.rm_rf(@kb_dir)
  end

  test "highlights round-trip: create, list in reading order, recolour, erase" do
    post kb_annotations_path(src: 0, file: "papers/study.pdf"),
         params: { annotation: mark(page: 2, start_offset: 4, quote: "later") }, as: :json
    assert_response :created
    post kb_annotations_path(src: 0, file: "papers/study.pdf"),
         params: { annotation: mark(page: 1, start_offset: 10, quote: "earlier", style: "underline") }, as: :json
    assert_response :created
    id = response.parsed_body["id"]

    get kb_annotations_path(src: 0, file: "papers/study.pdf"), as: :json
    assert_equal %w[earlier later], response.parsed_body.map { |m| m["quote"] }
    assert_equal "underline", response.parsed_body.first["style"]

    patch kb_annotation_path(id), params: { annotation: { color: "pink", quote: "hijack" } }, as: :json
    assert_response :success
    assert_equal ["pink", "earlier"], KbAnnotation.find(id).values_at(:color, :quote)

    delete kb_annotation_path(id), as: :json
    assert_response :no_content
    assert_equal 1, @user.kb_annotations.count
  end

  test "rejects bad marks and files outside the KB" do
    post kb_annotations_path(src: 0, file: "papers/study.pdf"),
         params: { annotation: mark(color: "plaid") }, as: :json
    assert_response :unprocessable_content

    post kb_annotations_path(src: 0, file: "../../config/database.yml"),
         params: { annotation: mark }, as: :json
    assert_response :not_found
    assert_equal 0, @user.kb_annotations.count
  end

  test "marks follow their file through rename and are dropped on delete" do
    post kb_annotations_path(src: 0, file: "papers/study.pdf"), params: { annotation: mark }, as: :json

    patch kb_fs_rename_path, params: { src: 0, path: "papers", name: "research" }, as: :json
    assert_equal ["research/study.pdf"], @user.kb_annotations.pluck(:relative_path)

    delete kb_fs_delete_path, params: { src: 0, path: "research/study.pdf" }
    assert_equal 0, @user.kb_annotations.count
  end

  test "agent context and tools see the highlighted passages" do
    post kb_annotations_path(src: 0, file: "papers/study.pdf"),
         params: { annotation: mark(page: 3, quote: "the key finding") }, as: :json

    context = Kb::ContextReader.new(base: @kb_dir, relative_path: "papers/study.pdf", kind: "file", user: @user).call
    assert_includes context, "- [p.3] the key finding"

    result = LocalAgent::Toolbox.new(user: @user).call("list_kb_highlights", { "src" => 0, "file" => "papers/study.pdf" })
    assert_equal [["papers/study.pdf", 3, "the key finding"]],
                 result.fetch(:kb_highlights).map { |h| h.values_at(:file, :page, :quote) }
  end

  private

  def mark(quote: "text", start_offset: 0, **attrs)
    { style: "highlight", color: "yellow", start_offset: start_offset, end_offset: start_offset + quote.length,
      quote: quote, prefix: "", suffix: "" }.merge(attrs)
  end
end
