require "test_helper"

class KbProjectsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @original_settings = @user.settings.deep_dup
    @kb_dir = Rails.root.join("tmp", "kb-projects-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @user.update!(settings: (@user.settings || {}).merge("kb" => { "folders" => [ @kb_dir ], "hide_native" => true }))
  end

  teardown do
    @user.update!(settings: @original_settings)
    FileUtils.rm_rf(@kb_dir)
  end

  def make_project
    Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Ferment")
  end

  test "creates a private project from the tree and a placeholder when unnamed" do
    post kb_fs_create_path, params: { src: 0, dir: "", name: "Yeast", kind: "project" }
    assert Kb::Project.at(@kb_dir, "Yeast")&.private?

    post kb_fs_create_path, params: { src: 0, dir: "", kind: "project" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert Kb::Project.at(@kb_dir, "Untitled project")
    assert_select ".kb-project-row"
  end

  test "converts an existing folder in place" do
    FileUtils.mkdir_p(File.join(@kb_dir, "old"))
    post kb_project_convert_path, params: { src: 0, path: "old" }
    assert Kb::Project.at(@kb_dir, "old")
  end

  test "project page renders and rejects non-projects and traversal" do
    make_project
    get kb_project_path(src: 0, path: "Ferment")
    assert_response :success
    assert_select ".kbp-title", text: "Ferment"

    FileUtils.mkdir_p(File.join(@kb_dir, "plain"))
    get kb_project_path(src: 0, path: "plain")
    assert_response :not_found
    get kb_project_path(src: 0, path: "../etc")
    assert_response :not_found
  end

  test "updates conclusion and toggles private" do
    make_project
    patch kb_project_path, params: { src: 0, path: "Ferment", conclusion: "Works at **4C**", goal: "Survive" }
    project = Kb::Project.at(@kb_dir, "Ferment")
    assert_equal "Works at **4C**", project.conclusion
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-prose strong", text: "4C"

    patch kb_project_path, params: { src: 0, path: "Ferment", private: "0" }
    refute Kb::Project.at(@kb_dir, "Ferment").private?
    patch kb_project_path, params: { src: 0, path: "Ferment", private: "1" }
    assert Kb::Project.at(@kb_dir, "Ferment").private?
  end

  test "creates a test, logs runs with an upload, and compares measurements" do
    project = make_project
    post kb_project_tests_path, params: { src: 0, dir: "Ferment", name: "Cold", objective: "Survives" },
                                headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[action=replace][target=kb-sidebar-tree]"
    test_rel = "Ferment/Tests/Cold"
    assert File.file?(File.join(@kb_dir, test_rel, ".kb-test.yml"))

    upload = Rack::Test::UploadedFile.new(StringIO.new("png"), "image/png", original_filename: "../shot.png")
    post kb_project_runs_path, params: { src: 0, path: test_rel, date: "2026-10-06", result: "ok",
                                         measurements: [ { name: "pH", value: "4.0", unit: "" } ], files: [ upload ] }
    post kb_project_runs_path, params: { src: 0, path: test_rel, date: "2026-10-20",
                                         measurements: [ { name: "pH", value: "4.5", unit: "" } ] }

    runs = Kb::Project.at(@kb_dir, "Ferment").tests.first.runs
    assert_equal %w[2026-10-06 2026-10-20], runs.map(&:name)
    assert_equal [ "shot.png" ], runs.first.files
    assert_equal "ok", runs.first.result

    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-compare th[scope=row]", text: "pH"
    assert_select ".kbp-delta.is-up", text: "+0.5"
    assert_select ".kbp-thumb img"

    patch kb_project_runs_path, params: { src: 0, path: runs.last.rel, date: "2026-10-20", conditions: "4C",
                                          measurements: [ { name: "pH", value: "4.1", unit: "" } ] }
    assert_equal "4C", Kb::Project.at(@kb_dir, "Ferment").tests.first.runs.last.conditions
  end

  test "rejects test and run paths outside the project" do
    make_project
    FileUtils.mkdir_p(File.join(@kb_dir, "elsewhere", "2026-01-01"))
    post kb_project_runs_path, params: { src: 0, path: "Ferment/../elsewhere", date: "2026-10-06" }
    assert_response :not_found
    post kb_project_tests_path, params: { src: 0, dir: "Ferment/sub", name: "x" }
    assert_not File.exist?(File.join(@kb_dir, "Ferment", "Tests", "x"))
  end

  test "new test without a name returns a placeholder for inline naming" do
    make_project
    post kb_project_tests_path, params: { src: 0, dir: "Ferment" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert File.directory?(File.join(@kb_dir, "Ferment", "Tests", "Untitled test"))
    assert_select ".kb-node-name-input[data-kb-autofocus]"
  end

  test "deletes a test folder with its runs, including hand-made tests" do
    project = make_project
    test = project.create_test!(name: "Fridge")
    test.create_run!(date: "2026-10-06")
    FileUtils.mkdir_p(File.join(project.abs, "Tests", "By hand"))

    delete kb_project_tests_path, params: { src: 0, path: test.rel }
    assert_not File.exist?(test.abs)
    delete kb_project_tests_path, params: { src: 0, path: "Ferment/Tests/By hand" }
    assert_not File.exist?(File.join(project.abs, "Tests", "By hand"))
    assert File.directory?(File.join(project.abs, "Tests"))
  end

  test "test deletion only touches folders directly under the project's Tests" do
    project = make_project
    run = project.create_test!(name: "Fridge").create_run!(date: "2026-10-06")
    File.write(File.join(project.abs, "notes.md"), "x")

    [ run.rel, "Ferment/notes.md", "Ferment/Tests", "Ferment", "Ferment/Tests/../notes.md" ].each do |path|
      delete kb_project_tests_path, params: { src: 0, path: path }
    end
    assert File.exist?(run.abs)
    assert File.exist?(File.join(project.abs, "notes.md"))
  end
end
