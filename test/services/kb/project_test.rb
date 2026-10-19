require "test_helper"

class Kb::ProjectFoundationTest < ActiveSupport::TestCase
  setup { @base = Dir.mktmpdir }
  teardown { FileUtils.rm_rf(@base) }

  test "create project, test, runs with same-day collision" do
    project = Kb::Project.create!(base: @base, parent_rel: "", name: "Ferment", goal: "survive?")
    assert project.private?
    assert_equal "active", project.status
    assert project.id.present?
    assert_equal project.id, Kb::Project.at(@base, "Ferment").id
    assert_equal "Ferment", Kb::Project.containing(@base, "Ferment/Tests/x/y.md").name

    test = project.create_test!(name: "Cold", objective: "4C", protocol: "steps")
    assert_equal [ "Cold" ], project.tests.map(&:name)
    r1 = test.create_run!(date: "2026-10-06", result: "ok", measurements: [ { name: "pH", value: 4.2 }, { name: "" } ])
    r2 = test.create_run!(date: Date.new(2026, 10, 6))
    assert_equal "2026-10-06", r1.name
    assert_equal "2026-10-06 (2)", r2.name
    assert_equal Date.new(2026, 10, 6), r1.date
    assert_equal [ { "name" => "pH", "value" => "4.2", "unit" => "" } ], r1.measurements
    assert_equal 2, test.runs.size

    File.write(File.join(@base, r1.rel, "photo.jpg"), "x")
    assert_equal [ "photo.jpg" ], r1.files
    r1.update!(result: "changed")
    assert_equal "changed", Kb::TestRun.new(@base, r1.rel).result
    project.update!(status: "concluded", conclusion: "yes", private: false)
    reloaded = Kb::Project.at(@base, "Ferment")
    assert_equal "concluded", reloaded.status
    assert_not reloaded.private?
    assert_raises(ArgumentError) { project.update!(status: "bogus") }
  end

  test "malformed yaml tolerated and fails closed" do
    FileUtils.mkdir_p(File.join(@base, "P/Tests/T/2026-01-01"))
    File.write(File.join(@base, "P/.kb-project.yml"), "{{{ not yaml")
    File.write(File.join(@base, "P/Tests/T/.kb-test.yml"), "- a\n- b")
    project = Kb::Project.at(@base, "P")
    assert project.private?
    assert_equal "", project.goal
    test = project.tests.first
    assert_equal "", test.objective
    assert_equal Date.new(2026, 1, 1), test.runs.first.date
    assert_nil Kb::Project.at(@base, "Missing")
  end

  test "rejects bad names and traversal" do
    assert_raises(ArgumentError) { Kb::Project.create!(base: @base, parent_rel: "", name: "../x") }
    assert_raises(ArgumentError) { Kb::Project.create!(base: @base, parent_rel: "", name: ".hidden") }
    assert_raises(ArgumentError) { Kb::Project.create!(base: @base, parent_rel: "../", name: "x") }
    Kb::Project.create!(base: @base, parent_rel: "", name: "A")
    assert_raises(ArgumentError) { Kb::Project.create!(base: @base, parent_rel: "", name: "A") }
    assert_nil Kb::Project.at(@base, "../")
  end

  test "symlink escape is rejected" do
    outside = Dir.mktmpdir
    File.write(File.join(outside, ".kb-project.yml"), "private: false")
    File.symlink(outside, File.join(@base, "link"))
    assert_nil Kb::Project.at(@base, "link")
    assert_raises(ArgumentError) { Kb::Project.create!(base: @base, parent_rel: "link", name: "x") }
  ensure
    FileUtils.rm_rf(outside)
  end

  def project_with_files
    project = Kb::Project.create!(base: @base, parent_rel: "", name: "P")
    FileUtils.mkdir_p(File.join(@base, "P/Tests/T"))
    FileUtils.mkdir_p(File.join(@base, "P/dir"))
    File.write(File.join(@base, "P/a.md"), "x")
    File.write(File.join(@base, "P/.hidden"), "x")
    project
  end

  test "stages default, normalize, validate" do
    project = project_with_files
    assert_equal %w[Frame Research Test Conclude], project.stages
    assert_equal "Frame", project.stage

    project.update!(stages: " A \n\na\nB\n" + "x" * 41 + "\nC")
    assert_equal %w[A B C], project.stages
    project.update!(stages: %w[One Two Three Four Five Six Seven Eight Nine])
    assert_equal 8, project.stages.size
    assert_raises(ArgumentError) { project.update!(stages: " \n ") }
    assert_raises(ArgumentError) { project.update!(stages: []) }
    assert_equal 8, Kb::Project.at(@base, "P").stages.size
  end

  test "stage validated and reset when removed" do
    project = project_with_files
    project.update!(stage: "Test")
    assert_equal "Test", Kb::Project.at(@base, "P").stage
    assert_raises(ArgumentError) { project.update!(stage: "Nope") }
    project.update!(stages: "Frame\nShip")
    assert_equal "Frame", project.stage
    project.update!(stage: "Ship")
    project.update!(stages: "Ship\nMore")
    assert_equal "Ship", project.stage
    project.update!(stages: "Only", stage: "Bogus")
    assert_equal "Only", project.stage
  end

  test "update_material! validates and persists" do
    project = project_with_files
    assert_equal({ "role" => nil, "stage" => "", "note" => "" }, project.material("a.md"))
    project.update_material!("a.md", role: "reference", stage: "Research", note: "n" * 300)
    reloaded = Kb::Project.at(@base, "P").material("a.md")
    assert_equal "reference", reloaded["role"]
    assert_equal "Research", reloaded["stage"]
    assert_equal 280, reloaded["note"].size
    project.update_material!("dir", role: "output", stage: "", note: "")
    assert_equal "output", project.material("dir")["role"]

    assert_raises(ArgumentError) { project.update_material!("a.md", role: "bogus") }
    assert_raises(ArgumentError) { project.update_material!("a.md", role: "working", stage: "Nope") }
    %w[Tests .hidden missing ../x a/b].each do |bad|
      assert_raises(ArgumentError, bad) { project.update_material!(bad, role: "working") }
    end
    File.symlink(File.join(@base, "P/a.md"), File.join(@base, "P/link"))
    assert_raises(ArgumentError) { project.update_material!("link", role: "working") }
  end

  test "update_material! all blank deletes the key; generic update! cannot write materials" do
    project = project_with_files
    project.update_material!("a.md", role: "working")
    project.update_material!("a.md", role: "", stage: "", note: "  ")
    assert_not YAML.load_file(File.join(@base, "P/.kb-project.yml"), permitted_classes: [ Time ])["materials"].key?("a.md")
    project.update!(materials: { "evil" => { "role" => "working" } })
    assert_empty YAML.load_file(File.join(@base, "P/.kb-project.yml"), permitted_classes: [ Time ])["materials"]
  end

  test "rename_material! moves the key and ignores absent" do
    project = project_with_files
    project.update_material!("a.md", role: "working", note: "hi")
    project.rename_material!("a.md", "b.md")
    assert_equal "hi", project.material("b.md")["note"]
    assert_nil project.material("a.md")["role"]
    assert_nothing_raised { project.rename_material!("zzz", "y") }
  end

  test "test stage is validated against project stages" do
    project = project_with_files
    test = project.create_test!(name: "Cold")
    assert_equal "", test.stage
    test.update!(stage: "Test")
    assert_equal "Test", Kb::ProjectTest.new(@base, test.rel, project).stage
    test.update!(stage: "")
    assert_raises(ArgumentError) { test.update!(stage: "Nope") }
  end

  test "stage_mode maps names by keyword then falls back by position" do
    project = Kb::Project.create!(base: @base, parent_rel: "", name: "P")
    assert_equal %w[frame research test conclude], project.stages.map { |st| project.stage_mode(st) }
    project.update!(stages: "Alpha\nBeta\nGamma")
    assert_equal %w[frame research conclude], %w[Alpha Beta Gamma].map { |st| project.stage_mode(st) }
    assert_equal "frame", project.stage_mode
    project.update!(stages: "Solo")
    assert_equal "frame", project.stage_mode
    project.update!(stages: "Experiments\nShip it")
    assert_equal %w[test conclude], project.stages.map { |st| project.stage_mode(st) }
  end

  test "brief and concluded_on follow status" do
    project = Kb::Project.create!(base: @base, parent_rel: "", name: "P")
    project.update!(brief: "## Question")
    assert_equal "## Question", project.brief
    assert_nil project.concluded_on
    project.update!(status: "concluded")
    assert_equal Date.current, project.concluded_on
    File.write(File.join(project.abs, ".kb-project.yml"), YAML.dump(project.send(:meta).merge("concluded_on" => "2026-01-02")))
    project = Kb::Project.at(@base, "P")
    project.update!(status: "concluded", goal: "x")
    assert_equal Date.new(2026, 1, 2), Kb::Project.at(@base, "P").concluded_on
    project.update!(status: "paused")
    assert_nil Kb::Project.at(@base, "P").concluded_on
  end

  test "test verdict defaults to open and rejects unknown values" do
    project = Kb::Project.create!(base: @base, parent_rel: "", name: "P")
    test = project.create_test!(name: "T")
    assert_equal "open", test.verdict
    test.update!(verdict: "supported")
    assert_equal "supported", project.tests.first.verdict
    assert_raises(ArgumentError) { test.update!(verdict: "maybe") }
  end

  test "findings add, update, remove and aggregate across owners" do
    project = Kb::Project.create!(base: @base, parent_rel: "", name: "P")
    test = project.create_test!(name: "T")
    assert_empty project.all_findings

    first = project.add_finding!("  Yeast likes 4C  ")
    assert_equal "Yeast likes 4C", first["text"]
    assert_equal Date.current.iso8601, first["at"]
    assert_match(/\A\h{8}\z/, first["id"])
    other = test.add_finding!("pH drops")

    assert_equal "Changed", project.update_finding!(first["id"], "Changed")["text"]
    assert_equal [ "Changed" ], Kb::Project.at(@base, "P").findings.map { |f| f["text"] }
    assert_equal [ project.rel, test.rel ], project.all_findings.map { |g| g[:owner].rel }
    assert_equal [ other ], project.all_findings.last[:items]

    assert_raises(ArgumentError) { project.add_finding!("  ") }
    assert_raises(ArgumentError) { project.update_finding!("nope", "x") }
    assert_raises(ArgumentError) { project.remove_finding!("nope") }
    assert_equal 2000, project.add_finding!("a" * 3000)["text"].length

    test.remove_finding!(other["id"])
    assert_empty test.findings
    assert_equal [ project.rel ], project.all_findings.map { |g| g[:owner].rel }
  end

  test "malformed findings are dropped" do
    project = Kb::Project.create!(base: @base, parent_rel: "", name: "P")
    File.write(File.join(project.abs, ".kb-project.yml"), "findings:\n  - nope\n  - {id: a, text: ' '}\n  - {id: b, text: ok, at: 2026-01-01}\n")
    assert_equal [ { "id" => "b", "text" => "ok", "at" => "2026-01-01" } ], Kb::Project.at(@base, "P").findings
  end
end
