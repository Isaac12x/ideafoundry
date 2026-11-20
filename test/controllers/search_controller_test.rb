require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Zebrafish tracker")
    @idea.notes.create!(body: "remember the zebrafish tank")
    @user.topologies.create!(name: "Zebra tools", topology_type: :custom)
  end

  test "groups hits by type and skips empty groups" do
    get global_search_path, params: { q: "zebra" }
    groups = response.parsed_body["groups"].to_h { |g| [ g["label"], g["items"] ] }
    assert_equal [ "Ideas", "Notes", "Topologies" ], groups.keys
    assert_equal idea_path(@idea), groups["Ideas"].first["url"]
  end

  test "versions of an idea are told apart by their version label" do
    @idea.create_new_version!
    get global_search_path, params: { q: "zebrafish" }
    titles = response.parsed_body["groups"].find { |g| g["label"] == "Ideas" }["items"].map { |i| i["title"] }
    assert_equal [ "Zebrafish tracker · v1", "Zebrafish tracker · v2" ], titles.sort
  end

  test "finds a description-only draft and titles it from the description" do
    draft = @user.ideas.create!(draft: true, title: "", description: "<div>Quokka sanctuary pitch<br>more</div>", state: :idea_new)
    get global_search_path, params: { q: "quokka" }
    groups = response.parsed_body["groups"].to_h { |g| [ g["label"], g["items"] ] }
    assert_equal "Quokka sanctuary pitch", groups["Drafts"].first["title"]
    assert_equal edit_idea_path(draft, draft: 1), groups["Drafts"].first["url"]
  end

  test "blank query returns nothing" do
    get global_search_path, params: { q: " " }
    assert_equal [], response.parsed_body["groups"]
  end

  test "every result type links to a page that resolves (folders and projects used to 404)" do
    use_kb_folder
    FileUtils.mkdir_p(File.join(@kb_dir, "plain-folder"))
    File.write(File.join(@kb_dir, "plain-folder", "plainfile.md"), "# hi")
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Plainproject")

    get global_search_path, params: { q: "plain" }
    items = response.parsed_body["groups"].find { |g| g["label"] == "Knowledge Base" }["items"]
    assert_equal %w[dir file project], items.map { |i| i["kind"] }.sort
    items.each do |i|
      get i["url"]
      assert_response :success, "#{i['kind']} #{i['url']}"
      case i["kind"]
      when "project" # the page lives in the kb-content frame
        assert_select "turbo-frame#kb-content[src=?]", kb_project_path(src: 0, path: "Plainproject")
        get kb_project_path(src: 0, path: "Plainproject")
        assert_response :success
      when "dir" then assert_equal kb_path(src: 0, folder: "plain-folder"), i["url"]
      end
    end

    [ [ "Ideas", "zebra" ], [ "Notes", "zebra" ], [ "Topologies", "zebra" ] ].each do |label, q|
      get global_search_path, params: { q: q }
      response.parsed_body["groups"].find { |g| g["label"] == label }["items"].each do |i|
        get i["url"]
        assert_response :success, "#{label} #{i['url']}"
      end
    end
  end

  test "items carry drill-in actions" do
    get global_search_path, params: { q: "zebrafish" }
    actions = response.parsed_body["groups"].first["items"].first["actions"].map { |a| a["label"] }
    assert_includes actions, "Open"
    assert_includes actions, "Edit"
    assert_includes actions, "Find similar"
    assert_includes actions, "Archive"
  end

  test "similar ranks the idea sharing the most terms first and leaves the seed out" do
    close = @user.ideas.create!(title: "Aquarium zebrafish filter", tldr: "tank filter for zebrafish")
    far = @user.ideas.create!(title: "Tax paperwork")
    get global_search_path, params: { mode: "similar", idea: @idea.id }
    titles = response.parsed_body["groups"].find { |g| g["label"] == "Ideas" }["items"].map { |i| i["title"] }
    assert_equal close.title, titles.first
    assert_not_includes titles, @idea.title
    assert_not_includes titles, far.title
  end

  test "similar with typed text ranks against ideas" do
    get global_search_path, params: { mode: "similar", q: "zebrafish tank" }
    assert_equal "Zebrafish tracker", response.parsed_body["groups"].first["items"].first["title"]
  end

  test "deep finds words inside descriptions, notes and KB files, with snippets and terms" do
    use_kb_folder
    File.write(File.join(@kb_dir, "log.md"), "Long prelude. The axolotl regeneration experiment worked.")
    File.write(File.join(@kb_dir, "clip.mp4.vtt"), "WEBVTT\n\n00:01.000 --> 00:02.000\naxolotl feeding time")
    @user.ideas.create!(title: "Pond", description: "<div>Notes on axolotl care and regeneration</div>")

    get global_search_path, params: { mode: "deep", q: "axolotl regeneration" }
    body = response.parsed_body
    assert_equal %w[axolotl regeneration], body["terms"]
    groups = body["groups"].to_h { |g| [ g["label"], g["items"] ] }
    assert_equal "Pond", groups["Ideas"].first["title"]
    assert_match(/axolotl/i, groups["Ideas"].first["snippet"])
    assert_equal [ "log.md" ], groups["Knowledge Base"].map { |i| i["title"] } # the .vtt lacks "regeneration"

    get global_search_path, params: { mode: "deep", q: "axolotl" }
    kb = response.parsed_body["groups"].find { |g| g["label"] == "Knowledge Base" }["items"].map { |i| i["title"] }
    assert_includes kb, "clip.mp4.vtt"
  end

  private

  def use_kb_folder
    @kb_dir = Rails.root.join("tmp", "kb-search-test-#{SecureRandom.hex(8)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @orig_settings = @user.settings.deep_dup
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    FileUtils.rm_rf(@kb_dir) if @kb_dir
    @user.update!(settings: @orig_settings) if @orig_settings
  end
end
