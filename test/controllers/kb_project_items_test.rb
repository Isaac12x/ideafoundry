require "test_helper"

class KbProjectItemsTest < ActionDispatch::IntegrationTest
  PNG = "data:image/png;base64,#{Base64.strict_encode64('\x89PNG fake')}".freeze

  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-items-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
    @project = Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Ferment")
    @test = @project.create_test!(name: "Cold", objective: "line one\nline two\n\n```\ncode\n```")
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "objective keeps its line breaks and code blocks through the shared renderer" do
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-objective .kb-markdown br"
    assert_select ".kbp-objective pre code", text: /code/
  end

  test "a requirement is stored and shows as a chip linking to the pinned idea version" do
    v1 = @user.ideas.create!(title: "Heat pump", state: :idea_new, attempt_count: 0)
    v3 = @user.ideas.create!(title: "Heat pump", state: :idea_new, attempt_count: 0, version_group_id: v1.id, version_number: 3)
    post kb_project_requirements_path, params: { src: 0, path: "Ferment", test: @test.rel, text: "@[Heat pump](idea:#{v3.id})" }

    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-req a.kb-ref[href=?]", "/ideas/#{v3.id}", text: "Heat pump · v3"

    id = Kb::ProjectTest.new(@kb_dir, @test.rel, @project).requirements.first["id"]
    delete kb_project_requirements_path, params: { src: 0, path: "Ferment", test: @test.rel, id: id }
    assert_empty Kb::ProjectTest.new(@kb_dir, @test.rel, @project).requirements
  end

  test "@ search finds idea versions by 'name v3', and maxims" do
    v1 = @user.ideas.create!(title: "Heat pump", state: :idea_new, attempt_count: 0)
    v3 = @user.ideas.create!(title: "Heat pump", state: :idea_new, attempt_count: 0, version_group_id: v1.id, version_number: 3)
    @user.maxims.create!(body: "Heat what you measure")

    get kb_mentions_path(q: "heat pump v3")
    ideas = response.parsed_body["results"].select { |r| r["kind"] == "idea" }
    assert_equal [ "@[Heat pump · v3](idea:#{v3.id})" ], ideas.map { |r| r["token"] }

    get kb_mentions_path(q: "heat")
    assert_includes response.parsed_body["results"].map { |r| r["kind"] }, "maxim"
  end

  test "drawings are saved with their source, served as png, and re-saved in place" do
    scope = { src: 0, path: "Ferment" }
    post kb_project_drawings_path(scope), params: { drawing: { title: "Sketch", content: { elements: [ { id: "a" } ], files: {} }, png_data_url: PNG } }, as: :json
    assert_response :created
    drawing = response.parsed_body
    assert_match %r{/knowledge-base/projects/drawings/[0-9a-f]{8}\.png\?}, drawing["png_url"]
    assert File.file?(File.join(@kb_dir, "Ferment", ".drawings", "#{drawing['id']}.excalidraw"))

    get drawing["png_url"]
    assert_response :success
    assert_equal "image/png", response.media_type

    get kb_project_drawing_path(drawing["id"], scope), headers: { "Accept" => "application/json" }
    assert_equal "a", response.parsed_body.dig("content", "elements", 0, "id")

    patch kb_project_drawing_path(drawing["id"], scope), params: { drawing: { title: "Renamed", content: { elements: [] } } }, as: :json
    assert_equal drawing["id"], response.parsed_body["id"]

    get kb_project_drawing_path("nothex", scope), headers: { "Accept" => "application/json" }
    assert_response :unprocessable_content
  end
end
