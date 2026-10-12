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
    assert_equal ["Cold"], project.tests.map(&:name)
    r1 = test.create_run!(date: "2026-10-06", result: "ok", measurements: [{ name: "pH", value: 4.2 }, { name: "" }])
    r2 = test.create_run!(date: Date.new(2026, 10, 6))
    assert_equal "2026-10-06", r1.name
    assert_equal "2026-10-06 (2)", r2.name
    assert_equal Date.new(2026, 10, 6), r1.date
    assert_equal [{ "name" => "pH", "value" => "4.2", "unit" => "" }], r1.measurements
    assert_equal 2, test.runs.size

    File.write(File.join(@base, r1.rel, "photo.jpg"), "x")
    assert_equal ["photo.jpg"], r1.files
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
end
