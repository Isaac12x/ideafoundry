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

  test "naming a test busts the tree cache so it shows in the sidebar" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    make_project
    get kb_tree_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

    post kb_project_tests_path, params: { src: 0, dir: "Ferment", name: "Cold" },
                                headers: { "Accept" => "text/vnd.turbo-stream.html" }
    get kb_tree_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_includes response.body, "Cold"
  ensure
    Rails.cache = original_cache
  end

  test "updates stage and stages" do
    make_project
    patch kb_project_path, params: { src: 0, path: "Ferment", stages: "A\nB", stage: "B" }
    project = Kb::Project.at(@kb_dir, "Ferment")
    assert_equal %w[A B], project.stages
    assert_equal "B", project.stage
    patch kb_project_path, params: { src: 0, path: "Ferment", stage: "Nope" }
    assert_equal "B", Kb::Project.at(@kb_dir, "Ferment").stage
  end

  test "project page shelves materials by role with an inbox and a stage rail" do
    make_project
    File.write(File.join(@kb_dir, "Ferment/paper.pdf"), "x")
    File.write(File.join(@kb_dir, "Ferment/loose.txt"), "x")
    FileUtils.mkdir_p(File.join(@kb_dir, "Ferment/raw/sub"))
    Kb::Project.at(@kb_dir, "Ferment").update_material!("paper.pdf", role: "reference", stage: "Research", note: "key source")

    get kb_project_path(src: 0, path: "Ferment")
    assert_response :success
    assert_select ".kbp-stage.is-current", text: /Frame/
    assert_select ".kbp-mat", 3
    assert_select ".kbp-mat[data-stage='Research']", text: /key source/
    assert_select ".kbp-triage-btn", 6 # loose.txt + raw/ sit in the Inbox
    assert_select ".kbp-mat-name--dir", text: "raw/"
  end

  test "materials endpoint sets, clears and rejects bad names" do
    make_project
    File.write(File.join(@kb_dir, "Ferment/a.md"), "x")
    patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: "a.md", role: "reference", stage: "Research", note: "hi" }
    assert_redirected_to kb_project_path(src: "0", path: "Ferment")
    assert_equal "reference", Kb::Project.at(@kb_dir, "Ferment").material("a.md")["role"]

    get kb_project_path(src: 0, path: "Ferment")
    assert_response :success

    [ "nope.md", "../a.md", "Tests", "../../etc/passwd" ].each do |bad|
      patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: bad, role: "working" }
      assert_nil Kb::Project.at(@kb_dir, "Ferment").send(:meta)["materials"]&.dig(bad), bad
    end
    patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: "a.md", role: "bogus" }
    assert_equal "reference", Kb::Project.at(@kb_dir, "Ferment").material("a.md")["role"]

    patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: "a.md", role: "", stage: "", note: "" }
    assert_nil Kb::Project.at(@kb_dir, "Ferment").material("a.md")["role"]
  end

  test "materials endpoint 404s outside a project" do
    FileUtils.mkdir_p(File.join(@kb_dir, "plain"))
    patch kb_project_materials_path, params: { src: 0, path: "plain", name: "x", role: "working" }
    assert_response :not_found
  end

  test "project_entries shape and rename keeps materials" do
    project = make_project
    File.write(File.join(@kb_dir, "Ferment/A.MD"), "xyz")
    FileUtils.mkdir_p(File.join(@kb_dir, "Ferment/sub"))
    File.write(File.join(@kb_dir, "Ferment/sub/f.txt"), "")
    project.update_material!("A.MD", role: "output", note: "n")
    entries = KbController.new.send(:project_entries, project)
    file = entries.find { |e| e[:name] == "A.MD" }
    assert_equal({ dir: false, ext: "md", size: 3, count: nil, role: "output", stage: "", note: "n", rel: "Ferment/A.MD" },
                 file.slice(:dir, :ext, :size, :count, :role, :stage, :note, :rel))
    assert_kind_of Time, file[:mtime]
    dir = entries.find { |e| e[:name] == "sub" }
    assert_equal({ dir: true, ext: "", size: nil, count: 1, role: nil }, dir.slice(:dir, :ext, :size, :count, :role))

    patch kb_fs_rename_path, params: { src: 0, path: "Ferment/A.MD", name: "B.md" }
    assert_equal "output", Kb::Project.at(@kb_dir, "Ferment").material("B.md")["role"]
  end

  test "updates a test stage" do
    project = make_project
    project.create_test!(name: "Cold")
    patch kb_project_tests_path, params: { src: 0, path: "Ferment/Tests/Cold", stage: "Test" }
    assert_equal "Test", project.tests.first.stage
  end

  test "updates brief, concluded_on via status, and test verdict" do
    project = make_project
    project.create_test!(name: "Cold")
    patch kb_project_path, params: { src: 0, path: "Ferment", brief: "Why?", status: "concluded" }
    project = Kb::Project.at(@kb_dir, "Ferment")
    assert_equal "Why?", project.brief
    assert_equal Date.current, project.concluded_on

    patch kb_project_tests_path, params: { src: 0, path: "Ferment/Tests/Cold", verdict: "refuted" }
    assert_equal "refuted", project.tests.first.verdict
    patch kb_project_tests_path, params: { src: 0, path: "Ferment/Tests/Cold", verdict: "bogus" }
    assert_equal "refuted", project.tests.first.verdict
  end

  test "findings endpoints add, edit and remove on a project and on a test" do
    project = make_project
    test_rel = project.create_test!(name: "Cold").rel

    post kb_project_findings_path, params: { src: 0, path: "Ferment", text: "General" }
    post kb_project_findings_path, params: { src: 0, path: test_rel, text: "Specific" },
                                   headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    project = Kb::Project.at(@kb_dir, "Ferment")
    assert_equal [ "General" ], project.findings.map { |f| f["text"] }
    test = project.tests.first
    assert_equal [ "Specific" ], test.findings.map { |f| f["text"] }

    patch kb_project_findings_path, params: { src: 0, path: test_rel, id: test.findings.first["id"], text: "Edited" }
    assert_equal "Edited", Kb::Project.at(@kb_dir, "Ferment").tests.first.findings.first["text"]

    delete kb_project_findings_path, params: { src: 0, path: test_rel, id: test.findings.first["id"] }
    assert_empty Kb::Project.at(@kb_dir, "Ferment").tests.first.findings

    post kb_project_findings_path, params: { src: 0, path: "Ferment", text: " " }
    assert_equal 1, Kb::Project.at(@kb_dir, "Ferment").findings.size
  end

  test "findings endpoints reject non-owners and outside paths" do
    make_project
    FileUtils.mkdir_p(File.join(@kb_dir, "Ferment/sub"))
    FileUtils.mkdir_p(File.join(@kb_dir, "plain"))
    [ "Ferment/sub", "Ferment/Tests/ghost", "plain", "Ferment/../plain" ].each do |path|
      post kb_project_findings_path, params: { src: 0, path: path, text: "x" }
      assert_response :not_found, path
    end
    assert_empty Kb::Project.at(@kb_dir, "Ferment").findings
  end

  test "sidebar tree shelves project children by role, keeps Tests a real dir" do
    project = make_project
    File.write(File.join(project.abs, "paper.pdf"), "x")
    File.write(File.join(project.abs, "loose.txt"), "x")
    File.write(File.join(project.abs, "draft.md"), "x")
    FileUtils.mkdir_p(File.join(project.abs, "raw"))
    project.update_material!("paper.pdf", role: "reference")
    project.update_material!("draft.md", role: "working")
    project.update!(stage: "Test")
    project.create_test!(name: "Cold")

    get kb_tree_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select ".kb-project-stage .kb-stage-dot", 4
    assert_select ".kb-project-stage .kb-stage-dot.is-passed", 2
    assert_select ".kb-project-stage .kb-stage-dot.is-current:nth-child(3)"
    assert_select ".kb-project-stage .kb-stage-dot.is-end:nth-child(4)"
    assert_select ".kb-project-link[title='Stage: Test · Active']"
    assert_select ".kb-role-group--working .kb-role-label", text: "Working"
    assert_select ".kb-role-group--working .kb-role-count", text: "1"
    assert_select ".kb-role-group--inbox .kb-role-count", text: "2" # loose.txt + raw/
    assert_select ".kb-role-group--reference .kb-file-row[data-kb-tree-rel-param='Ferment/paper.pdf']"
    assert_select ".kb-role-group--output:not(.is-empty)", 0
    assert_select ".kb-role-group--output.is-empty .kb-role-header[data-kb-tree-role-param=output]", 1 # drop target while dragging
    assert_select ".kb-role-group--inbox .kb-role-header[data-kb-tree-role-param=''][data-kb-tree-project-rel-param=Ferment]", 1
    assert_select ".kb-role-group:not(.is-empty)[data-kb-folder-default-open-value=false]", 1 # reference
    assert_select ".kb-role-group:not(.is-empty) .kb-role-header[role=treeitem][aria-expanded]", 3
    assert_select ".kb-role-header[draggable], .kb-role-header[data-action*=contextmenu]", 0
    assert_select ".kb-dir-group[data-kb-folder-default-open-value=false] .kb-dir-header[data-kb-tree-tests-dir-param=true]"
    assert_select ".kb-dir-header[data-kb-tree-rel-param='Ferment/Tests/Cold']"
    assert_select ".kb-file-row[data-kb-tree-rel-param='Ferment/.kb-project.yml']", 0
  end

  test "tree drop re-roles only the role, keeps stage and note, and refreshes just the tree" do
    project = make_project
    File.write(File.join(project.abs, "a.txt"), "x")
    project.update_material!("a.txt", role: "working", stage: "Research", note: "keep me")
    patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: "a.txt", role: "output", tree_only: "1" },
                                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[action=replace][target=kb-sidebar-tree]"
    assert_select "turbo-stream[target=kb-content]", 0
    assert_equal({ "role" => "output", "stage" => "Research", "note" => "keep me" }, Kb::Project.at(@kb_dir, "Ferment").material("a.txt"))

    patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: "a.txt", role: "", tree_only: "1" }
    assert_nil Kb::Project.at(@kb_dir, "Ferment").material("a.txt")["role"]
    assert_equal "keep me", Kb::Project.at(@kb_dir, "Ferment").material("a.txt")["note"]

    patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: "../x", role: "output", tree_only: "1" }
    assert_nil Kb::Project.at(@kb_dir, "Ferment").material("a.txt")["role"] # bad name changed nothing
  end

  test "a role change from the page refreshes both the tree and the page" do
    project = make_project
    File.write(File.join(project.abs, "a.txt"), "x")
    patch kb_project_materials_path, params: { src: 0, path: "Ferment", name: "a.txt", role: "working", stage: "", note: "" },
                                     headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_select "turbo-stream[target=kb-sidebar-tree]"
    assert_select "turbo-stream[target=kb-content]"
  end

  test "conclude: empty conclusion shows the editor directly with a draft button, unsettled tests are a soft note" do
    project = make_project
    project.create_test!(name: "Cold")
    project.update!(stage: "Conclude")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select "#kbp-sec-conclusion details", 0
    assert_select "#kbp-sec-conclusion textarea[name=conclusion][placeholder]"
    assert_select "#kbp-sec-conclusion button[data-action='kb-project#draft']"
    assert_select ".kbp-todo-warn", text: /1 test without a verdict will show as open/
    assert_select ".kbp-todo", text: /No conclusion written/
    assert_select ".kbp-close-warn", text: /Cold/
    assert_select ".kbp-tools button[data-action='kb-project#copyReport'][data-markdown*='## Tests & results']"
    assert_select ".kbp-tools button[data-action='kb-project#print']"
    assert_select ".kbp-todo-item", text: /file to sort|no runs/, count: 0 # work is done: no chores
  end

  test "ledger drops measurements the table already shows" do
    project = make_project
    test = project.create_test!(name: "Cold")
    test.create_run!(date: "2026-10-06", conditions: "c1", measurements: [ { "name" => "pH", "value" => "4", "unit" => "" } ])
    project.update!(stage: "Test")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-compare"
    assert_select ".kbp-run .kbp-measures", 0
    assert_select ".kbp-run", text: /c1/
    assert_select ".kbp-caption", text: /oldest to newest/i
    assert_select ".kbp-caption", text: /newest first/i
  end

  def section_ids
    css_select(".kbp-sec").map { |n| n["id"].delete_prefix("kbp-sec-") }
  end

  test "each stage mode leads with its own section and default-open set" do
    project = make_project
    { "Frame" => %w[brief], "Research" => %w[materials findings], "Test" => %w[tests findings], "Conclude" => %w[conclusion summary results] }.each do |stage, leads|
      project.update!(stage: stage)
      get kb_project_path(src: 0, path: "Ferment")
      assert_equal leads.first, section_ids.first, stage
      leads.each { |id| assert_select "#kbp-sec-#{id}.is-open", 1, "#{stage}: #{id} open" }
      assert_select ".kbp-sec.kbp-sec--lead", 1
    end
    assert_select ".kbp--conclude"
  end

  test "test mode shows a strip and open cards with verdict selects; other modes collapse cards" do
    project = make_project
    project.create_test!(name: "Cold", objective: "Survives the fridge").update!(verdict: "supported")
    project.update!(stage: "Test")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-strip-item", 1
    assert_select ".kbp-test.is-open", 1
    assert_select ".kbp-test select[name=verdict][data-controller=select-menu] option[value=supported][selected]"
    assert_select ".kbp-test-line", text: /0 runs.*not run yet.*0 findings.*Survives the fridge/m

    project.update!(stage: "Research")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-test.is-open", 0
    assert_select ".kbp-strip", 0
  end

  test "conclude mode is a report with summary, results table and a close action" do
    project = make_project
    project.add_finding!("Grows slowly")
    test = project.create_test!(name: "Cold")
    test.update!(verdict: "refuted")
    test.add_finding!("Dies at day 3")
    test.create_run!(date: "2026-10-06", result: "All dead")
    project.update!(stage: "Conclude")

    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-fgroup", 2
    assert_select ".kbp-fgroup .kbp-verdict[data-tone=danger]", text: /Refuted/
    assert_select ".kbp-flist li", 2
    assert_select ".kbp-results tbody tr", 1
    assert_select ".kbp-results td.snippet", text: /All dead/
    assert_select "form.kbp-close input[name=status][value=concluded]"
    assert_select "form.kbp-close button", text: "Mark project concluded"
    assert_select ".kbp-stage.is-terminal.is-current"
    assert_select ".kbp-stage.is-complete", 0

    patch kb_project_path, params: { src: 0, path: "Ferment", status: "concluded" }
    get kb_project_path(src: 0, path: "Ferment")
    assert_select "form.kbp-close", 0
    assert_select ".kbp-concluded", text: /Concluded #{Date.current.day}/
    assert_select ".kbp-stage.is-complete .kbp-stage-note", text: "Complete"
    assert_select ".kbp-reopen input[value=active]"
  end

  test "findings forms post to the findings path with the owner rel" do
    project = make_project
    test = project.create_test!(name: "Cold")
    project.add_finding!("General one")
    test.add_finding!("Test one")
    project.update!(stage: "Test")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select "form.kbp-finding-add[action=?]", kb_project_findings_path, 2
    assert_select "form.kbp-finding-add input[name=path][value=?]", "Ferment"
    assert_select "form.kbp-finding-add input[name=path][value=?]", test.rel
    assert_select "form.kbp-finding-edit[action=?] input[name=id]", kb_project_findings_path, 2
    assert_select "form.kbp-finding-edit input[name=_method][value=patch]", 2
    assert_select "form[action=?] input[name=_method][value=delete]", kb_project_findings_path, 2
  end

  test "every select on the page is a select-menu" do
    project = make_project
    File.write(File.join(project.abs, "a.txt"), "x")
    File.write(File.join(project.abs, "b.txt"), "x")
    project.update_material!("b.txt", role: "working", stage: "", note: "")
    project.create_test!(name: "Cold")
    %w[Frame Research Test Conclude].each do |stage|
      project.update!(stage: stage)
      get kb_project_path(src: 0, path: "Ferment")
      assert_select "select", minimum: 4
      assert_select "select:not([data-controller=select-menu])", 0, stage
    end
    assert_select "select.kbp-status option[data-tone=success]"
  end

  test "materials stay collapsible with remembered state and a role summary" do
    project = make_project
    File.write(File.join(project.abs, "a.txt"), "x")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-group--inbox[data-controller=kb-collapse][data-kb-collapse-key-value*='group:inbox']"
    assert_select "#kbp-sec-materials .kbp-sum-alert", text: "1"
    assert_select "#kbp-sec-materials[data-controller=kb-collapse]"
    project.update!(stage: "Test")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select "#kbp-sec-materials:not(.is-open) .kbp-sec-body[hidden]"
  end

  test "frame shows the brief as three prompts with answered ones ticked, materials collapsed to an inbox count" do
    project = make_project
    File.write(File.join(project.abs, "a.txt"), "x")
    project.update!(brief: "## Question\nDoes it live?\n## Scope\n")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-prompt", 3
    assert_select ".kbp-prompt.is-done", 1
    assert_select "#kbp-sec-materials:not(.is-open) .kbp-sum-alert", text: "1"
    assert_select "textarea[name=brief]", text: /Does it live/
  end

  test "next line lists pending work and links to it; inbox rows are compact" do
    project = make_project
    File.write(File.join(project.abs, "a.txt"), "x")
    test = project.create_test!(name: "Cold")
    project.update!(stage: "Test")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-todo-item[data-target='kbp-sec-materials']", text: "1 file to sort"
    assert_select ".kbp-todo-item", text: "Cold: no runs yet"
    assert_select ".kbp-mat select[name=stage]", 0 # inbox rows get a stage after sorting
    assert_select ".kbp-mat .kbp-icon-btn[aria-label^='Add note']"
    assert_select ".kbp-stage-btn[aria-label='Move project to Research']"
    assert_select ".kbp-eyebrow .kbp-status"
    assert_select ".kbp-test .kbp-nudge", 0
    2.times { |i| test.create_run!(date: "2026-10-0#{i + 1}") }
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-test .kbp-nudge", text: "Ready for a verdict?"
    assert_select ".kbp-test.is-open", 1
  end

  test "single-run measurements get a table and conclude offers a draft button" do
    project = make_project
    test = project.create_test!(name: "Cold")
    test.create_run!(date: "2026-10-06", measurements: [ { "name" => "pH", "value" => "4", "unit" => "" } ])
    project.update!(stage: "Test")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-compare th[scope=row]", text: "pH"
    project.update!(stage: "Conclude")
    get kb_project_path(src: 0, path: "Ferment")
    assert_select "button[data-action='kb-project#draft'][data-draft*='## Cold']"
  end

  test "lock, locked page + tree, wrong password, unlock" do
    skip "7z not installed" unless Kb::ProjectLock.available?
    make_project
    File.write(File.join(@kb_dir, "Ferment", "a.md"), "x")
    post kb_project_lock_path, params: { src: 0, path: "Ferment", password: "hunter22", password_confirmation: "hunter22" }
    assert_redirected_to kb_project_path(src: 0, path: "Ferment")
    Kb::ProjectLock.wait_all
    assert_equal [ ".kb-project.yml", "Ferment.7z" ], Dir.children(File.join(@kb_dir, "Ferment")).sort

    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp--locked input[name=password]"
    assert_select ".kbp-title", text: /Ferment/
    get kb_tree_path
    assert_select ".kb-project-locked", text: /Locked/
    patch kb_project_path, params: { src: 0, path: "Ferment", goal: "x" }
    assert_redirected_to kb_project_path(src: 0, path: "Ferment")
    assert_equal "Project is locked. Unlock it first.", flash[:alert]

    post kb_project_unlock_path, params: { src: 0, path: "Ferment", password: "wrong-pass" }
    assert_equal "Wrong password.", flash[:alert]
    assert Kb::Project.at(@kb_dir, "Ferment").locked?

    post kb_project_unlock_path, params: { src: 0, path: "Ferment", password: "hunter22" }
    Kb::ProjectLock.wait_all
    assert_not Kb::Project.at(@kb_dir, "Ferment").locked?
    assert File.file?(File.join(@kb_dir, "Ferment", "a.md"))
  end

  test "while a lock runs: progress page, writes blocked, failure shown once" do
    make_project
    File.write(File.join(@kb_dir, "Ferment", "a.md"), "keep")
    gate = Queue.new
    Kb::ProjectLock.stub(:lock!, ->(*_a, **_k) { gate.pop }) do
      post kb_project_lock_path, params: { src: 0, path: "Ferment", password: "hunter22", password_confirmation: "hunter22" }

      get kb_project_path(src: 0, path: "Ferment")
      assert_select ".kbp-lock-working[role=status]", text: /Encrypting/
      assert_select "[data-controller=extraction-status][data-extraction-status-active-value=true]"

      delete kb_fs_delete_path, params: { src: 0, path: "Ferment/a.md" }
      post kb_fs_create_path, params: { src: 0, dir: "Ferment", name: "new.md" }
      post kb_fs_upload_path, params: { src: 0, dir: "Ferment", files: [ fixture_file_upload("test.txt", "text/plain") ] } if File.exist?(Rails.root.join("test/fixtures/files/test.txt"))
      patch kb_fs_save_path, params: { src: 0, file: "Ferment/a.md", content: "changed" }
      patch kb_project_path, params: { src: 0, path: "Ferment", goal: "x" }
      assert_match(/Try again/, flash[:alert])
      assert_equal "keep", File.read(File.join(@kb_dir, "Ferment", "a.md"))
      assert_not File.exist?(File.join(@kb_dir, "Ferment", "new.md"))

      gate << 1
      Kb::ProjectLock.wait_all
    end

    Kb::ProjectLock.stub(:lock!, ->(*_a, **_k) { raise Kb::ProjectLock::Error, "Could not create the archive." }) do
      post kb_project_lock_path, params: { src: 0, path: "Ferment", password: "hunter22", password_confirmation: "hunter22" }
      Kb::ProjectLock.wait_all
    end
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-lock-banner", text: /Could not create the archive/
    get kb_project_path(src: 0, path: "Ferment")
    assert_select ".kbp-lock-banner", count: 0
  end

  test "idea knowledge card shows Locked for a locked project, not stub stats" do
    skip "7z not installed" unless Kb::ProjectLock.available?
    make_project
    idea = @user.ideas.create!(title: "Linker")
    Kb::ProjectLock.lock!(Kb::Project.at(@kb_dir, "Ferment"), "hunter22")
    IdeaKbLink.create!(idea: idea, source_path: @kb_dir, relative_path: "Ferment", entry_type: "project")
    get idea_path(idea)
    assert_select ".idea-kb-links__meta", text: /Locked/
    assert_select ".idea-kb-links__meta", text: /0 tests/, count: 0
  end

  def make_locked_project
    project = make_project
    File.binwrite(File.join(project.abs, "Ferment.7z"), "x")
    Kb::ProjectLock.write_stub(project.abs, { "private" => true, "locked" => true, "archive" => "Ferment.7z" })
    File.write(File.join(@kb_dir, "other.md"), "# other")
    project
  end

  test "files inside a locked project open the locked page, never the archive" do
    make_locked_project

    get kb_file_path(src: 0, file: "Ferment/Ferment.7z")
    assert_redirected_to kb_project_path(src: 0, path: "Ferment")

    get kb_path
    assert_select "#kb-content", text: /Ferment\.7z/, count: 0
    assert_response :success
  end

  test "index never auto-opens the archive of a locked project" do
    File.delete(File.join(@kb_dir, "other.md")) if File.exist?(File.join(@kb_dir, "other.md"))
    make_locked_project
    File.delete(File.join(@kb_dir, "other.md"))
    get kb_path
    assert_response :success
    assert_no_match(/Download Ferment\.7z/, response.body)
  end

  test "a locked project row has no chevron and no children" do
    make_locked_project
    get kb_path
    assert_select ".kb-project-row .kb-dir-toggle", count: 0
    assert_select ".kb-project-row[aria-expanded]", count: 0
    assert_select ".kb-project-locked"
    assert_select ".kb-dir-children .kb-file-row", count: 0
  end

  test "downloads into a locked project are refused" do
    make_locked_project
    assert_no_difference -> { @user.kb_downloads.count } do
      post kb_fs_create_path, params: { src: 0, dir: "Ferment", name: "https://example.com/a.pdf", kind: "file" }
    end
  end

  test "creates and converts build plans and renders their checklist page" do
    post kb_fs_create_path, params: { src: 0, dir: "", kind: "project", project_kind: "build" }
    assert Kb::Project.at(@kb_dir, "Untitled build plan")&.build?

    FileUtils.mkdir_p(File.join(@kb_dir, "old"))
    post kb_project_convert_path, params: { src: 0, path: "old", project_kind: "build" }
    assert Kb::Project.at(@kb_dir, "old").build?

    File.write(File.join(@kb_dir, "guide.md"), "x")
    items = [ { title: "Joinery", status: "learning", links: "guide.md\nmissing.md" }, { title: "Roofing" } ].to_json
    patch kb_project_path, params: { src: 0, path: "old", goal: "Build a cabin", items: items }
    get kb_project_path(src: 0, path: "old")
    assert_response :success
    assert_select ".kbp--build"
    assert_select ".kbb-title[value=Joinery]"
    assert_select ".kbb-meter[max='2'][value='0']"
    assert_select ".kbb-links a[title='guide.md']"
    assert_select ".kbb-link-off", text: /missing/
    assert_select ".kbp-rail, .kbp-sec--tests", count: 0

    patch kb_project_path, params: { src: 0, path: "old", items: [ { title: "x", links: "../etc/passwd" } ].to_json }
    assert_equal 2, Kb::Project.at(@kb_dir, "old").items.size
    assert_match(/not a path inside the KB/, flash[:alert])
  end

  test "build plans refuse tests and the tree marks them" do
    post kb_fs_create_path, params: { src: 0, dir: "", name: "Cabin", kind: "project", project_kind: "build" }
    post kb_project_tests_path, params: { src: 0, dir: "Cabin", name: "T" }
    assert_empty Kb::Project.at(@kb_dir, "Cabin").tests
    get kb_path
    assert_select ".kb-build-group .kb-build-badge", text: "0/0"
    assert_select ".kb-build-group .kb-project-stage", count: 0
  end

  test "research projects ignore a checklist" do
    make_project
    patch kb_project_path, params: { src: 0, path: "Ferment", items: "[]" }
    assert_equal "Only build plans have a checklist.", flash[:alert]
  end
end
