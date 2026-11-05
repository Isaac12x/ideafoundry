require "test_helper"

class KbIdeaAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-attach-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    FileUtils.cp(file_fixture("ocr_sample.png"), File.join(@kb_dir, "shot.png"))
    @idea = @user.ideas.create!(title: "Fermentation notes", state: :idea_new)
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "attaches the png to the idea and returns a link" do
    assert_difference -> { @idea.attachments.count }, 1 do
      post kb_attach_to_idea_path, params: { src: 0, file: "shot.png", idea_id: @idea.id }
    end

    assert_response :created
    body = response.parsed_body
    assert_equal [ @idea.id, idea_path(@idea), false ], [ body["idea"]["id"], body["idea"]["url"], body["hero"] ]
    attachment = @idea.reload.attachments.first
    assert_equal "shot.png", attachment.filename.to_s
    assert_equal "image/png", attachment.content_type
    assert_equal File.binread(File.join(@kb_dir, "shot.png")), attachment.download
    assert_not @idea.hero_image.attached?
  end

  test "optionally sets it as the hero image too" do
    post kb_attach_to_idea_path, params: { src: 0, file: "shot.png", idea_id: @idea.id, hero: "1" }

    assert_response :created
    assert response.parsed_body["hero"]
    assert @idea.reload.hero_image.attached?
    assert_equal 1, @idea.attachments.count
  end

  test "rejects private projects, non-images, unknown ideas and traversal" do
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Secret")
    FileUtils.cp(file_fixture("ocr_sample.png"), File.join(@kb_dir, "Secret", "shot.png"))
    File.write(File.join(@kb_dir, "n.md"), "x")

    post kb_attach_to_idea_path, params: { src: 0, file: "Secret/shot.png", idea_id: @idea.id }
    assert_response :forbidden
    post kb_attach_to_idea_path, params: { src: 0, file: "n.md", idea_id: @idea.id }
    assert_response :unprocessable_content
    post kb_attach_to_idea_path, params: { src: 0, file: "shot.png", idea_id: 0 }
    assert_response :unprocessable_content
    post kb_attach_to_idea_path, params: { src: 0, file: "../shot.png", idea_id: @idea.id }
    assert_response :not_found
    assert_equal 0, @idea.reload.attachments.count
  end

  test "image and video views offer the attach panel" do
    get kb_file_path(src: 0, file: "shot.png")
    assert_select "[data-controller~=kb-idea-attach] button", text: /Attach to idea/
    assert_select ".kb-idea-attach input[type=search]"
    assert_select "[data-controller~=kb-image-text] .kb-image-text-layer"
  end
end
