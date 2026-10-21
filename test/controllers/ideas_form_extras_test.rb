require "test_helper"

class IdeasFormExtrasTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "idea-extras-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@kb_dir, "Lab"))
    File.write(File.join(@kb_dir, "Lab", ".kb-project.yml"), "id: x\ngoal: g\nstatus: active\nprivate: true\n")
    @user.update_kb_folders([ @kb_dir ])
    @src = 1
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  test "inline topology create returns json with node html and parent" do
    parent = @user.topologies.create!(name: "Food #{SecureRandom.hex(3)}", topology_type: :custom)
    post topologies_path(format: :json, picker: 1), params: { topology: { name: "Snacks", parent_id: parent.id } }, as: :json
    assert_response :created
    json = response.parsed_body
    assert_equal "Snacks", json["name"]
    assert_equal "#{parent.name} > Snacks", json["full_path"]
    assert_includes json["html"], %(value="#{json['id']}")
    assert_equal parent.id, Topology.find(json["id"]).parent_id
  end

  test "inline topology create reports validation errors" do
    @user.topologies.create!(name: "Dup", topology_type: :custom)
    assert_no_difference -> { Topology.count } do
      post topologies_path(format: :json), params: { topology: { name: "Dup" } }, as: :json
    end
    assert_response :unprocessable_content
    assert response.parsed_body["errors"]["name"].present?
  end

  test "project search lists projects on blank query, across sources" do
    get ideas_kb_link_search_path, params: { q: "" }
    results = response.parsed_body["results"]
    assert_equal [ "Lab" ], results.select { |r| r["source"] == File.basename(@kb_dir) }.map { |r| r["name"] }
    assert results.all? { |r| r["type"] == "project" }
  end

  test "create links picked KB projects and themes with the idea" do
    existing = @user.themes.create!(name: "Productizing #{SecureRandom.hex(3)}")
    assert_difference [ -> { Idea.count }, -> { IdeaKbLink.count } ], 1 do
      post ideas_path, params: { idea: { title: "Combo", theme_ids: [ "", existing.id ], new_theme_names: [ "Brand new" ] },
                                 kb_picks: [ "#{@src}:Lab" ] }
    end
    idea = Idea.find_by!(title: "Combo")
    assert_equal "project", idea.kb_links.first.entry_type
    assert_equal [ existing.name, "Brand new" ].sort, idea.themes.map(&:name).sort
  end

  test "create with an invalid pick leaves no idea behind" do
    assert_no_difference [ -> { Idea.count }, -> { IdeaKbLink.count }, -> { Theme.count } ] do
      post ideas_path, params: { idea: { title: "Orphan", new_theme_names: [ "Ghost" ] }, kb_picks: [ "#{@src}:Nope" ] }
    end
    assert_response :unprocessable_content
  end

  test "themes update and delete are user scoped" do
    theme = @user.themes.create!(name: "Productizing")
    other = User.where.not(id: @user.id).first&.themes&.create!(name: "Theirs")
    patch theme_path(theme), params: { theme: { name: "Shipping" } }
    assert_equal "Shipping", theme.reload.name
    if other
      delete theme_path(other)
      assert_response :not_found
      assert Theme.exists?(other.id)
    end
    delete theme_path(theme)
    assert_not Theme.exists?(theme.id)
  end

  test "set_themes assigns, creates on the fly and clears" do
    idea = @user.ideas.create!(title: "Themed")
    theme = @user.themes.create!(name: "T #{SecureRandom.hex(3)}")
    patch set_themes_idea_path(idea), params: { idea: { theme_ids: [ "", theme.id ], new_theme_names: [ "Fresh" ] } }
    assert_equal [ theme.name, "Fresh" ].sort, idea.reload.themes.map(&:name).sort
    patch set_themes_idea_path(idea), params: { idea: { theme_ids: [ "" ] } }
    assert_empty idea.reload.themes
  end

  test "index groups by theme, ideas appear in each theme, no theme last, and filters" do
    a = @user.themes.create!(name: "Alpha #{SecureRandom.hex(3)}")
    b = @user.themes.create!(name: "Beta #{SecureRandom.hex(3)}")
    both = @user.ideas.create!(title: "In both", themes: [ a, b ])
    only_b = @user.ideas.create!(title: "Only beta", themes: [ b ])
    none = @user.ideas.create!(title: "Nothing here")

    get ideas_path(group: "theme", reset: 1)
    assert_response :success
    body = response.body
    assert_equal 2, body.scan(%(idea-title">In both)).size
    assert body.index("Only beta")
    assert body.rindex("No theme") > body.rindex(a.name)
    assert body.index("Nothing here") > body.index("No theme")

    get ideas_path(theme_id: b.id, reset: 1)
    assert_includes response.body, "Only beta"
    assert_not_includes response.body, "Nothing here"

    get ideas_path(theme_id: "none", reset: 1)
    assert_includes response.body, "Nothing here"
    assert_not_includes response.body, "Only beta"
  ensure
    [ both, only_b, none ].compact.each(&:destroy)
  end

  test "edit form renders pickers" do
    idea = @user.ideas.create!(title: "Form")
    get edit_idea_path(idea)
    assert_response :success
    assert_select "[data-controller='theme-tokens']"
    assert_select "[data-controller~='kb-link-picks']"
    assert_select "[data-topology-picker-target='newPanel']"
  end
end
