require "test_helper"

class KbProjectHelperTest < ActionView::TestCase
  setup do
    @kb_dir = Rails.root.join("tmp", "kb-helper-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(@kb_dir)
    @project = Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Ferment", goal: "Does it survive?")
  end

  teardown { FileUtils.rm_rf(@kb_dir) }

  test "attention order: open verdicts first, then latest run, then name" do
    a = @project.create_test!(name: "A done old")
    a.update!(verdict: "supported")
    a.create_run!(date: "2026-01-01")
    b = @project.create_test!(name: "B done new")
    b.update!(verdict: "refuted")
    b.create_run!(date: "2026-02-01")
    c = @project.create_test!(name: "C open")
    assert_equal [ "C open", "B done new", "A done old" ], kb_attention_tests(@project).map(&:name)
    assert_equal [ c.rel ], kb_open_test_rels(kb_attention_tests(@project)).first(1)
    assert_includes kb_open_test_rels(kb_attention_tests(@project)), b.rel
    refute_includes kb_open_test_rels(kb_attention_tests(@project)), a.rel
  end

  test "at least one card opens when every test has a verdict and none ran" do
    t = @project.create_test!(name: "Only")
    t.update!(verdict: "supported")
    assert_equal [ t.rel ], kb_open_test_rels(@project.tests)
  end

  test "next actions are derived from state and capped at three" do
    File.write(File.join(@project.abs, "a.txt"), "x")
    fridge = @project.create_test!(name: "Fridge")
    two = @project.create_test!(name: "Two runs")
    2.times { |i| two.create_run!(date: "2026-03-0#{i + 1}") }
    entries = [ { role: nil } ]
    labels = kb_project_next(@project, entries, "test").map { |t| t[:label] }
    assert_equal [ "1 file to sort", "Two runs: 2 runs, no verdict", "Fridge: no runs yet" ], labels
    solo = Kb::Project.create!(base: @kb_dir, parent_rel: "", name: "Solo")
    assert_empty kb_project_next(solo, [], "test")
    assert_equal [ "No conclusion written" ], kb_project_next(solo, [], "conclude").map { |t| t[:label] }
  end

  test "brief checklist reads headings and Label: lines" do
    state = kb_brief_state("## Question\nDoes it live?\n## Scope\n\nScope: one strain\n## What counts as an answer\n")
    assert_equal({ question: true, scope: true, answer: false }, state)
    assert_equal({ question: true, scope: false, answer: true }, kb_brief_state("Question: x\nSuccess: yes"))
    assert_equal({ question: false, scope: false, answer: false }, kb_brief_state(BRIEF_TEMPLATE))
  end

  test "conclude next line only flags a missing conclusion; open tests are a separate soft warning" do
    @project.create_test!(name: "Fridge")
    File.write(File.join(@project.abs, "a.txt"), "x")
    assert_equal [ "No conclusion written" ], kb_project_next(@project, [ { role: nil } ], "conclude").map { |t| t[:label] }
    @project.update!(conclusion: "Done")
    assert_empty kb_project_next(@project, [ { role: nil } ], "conclude")
    assert_equal [ "Fridge" ], kb_unsettled_tests(@project).map(&:name)
  end

  test "conclusion draft: question, answer slot, tests by verdict with movement and numbered findings, not-run line, general" do
    @project.add_finding!("General thing")
    refuted = @project.create_test!(name: "Zed")
    refuted.update!(verdict: "refuted")
    refuted.add_finding!("It failed")
    ok = @project.create_test!(name: "Fridge")
    ok.update!(verdict: "supported")
    %w[92 81].each_with_index { |v, i| ok.create_run!(date: "2026-10-0#{i + 1}", measurements: [ { "name" => "viability", "value" => v, "unit" => "%" } ]) }
    ok.add_finding!("Held at 4C")
    @project.create_test!(name: "Idle A")
    @project.create_test!(name: "Idle B")

    draft = kb_conclusion_draft(@project)
    assert_match(/\A# Does it survive\?\n\n\*\*Answer:\*\*/, draft)
    assert_operator draft.index("## Fridge"), :<, draft.index("## Zed") # supported before refuted
    assert_includes draft, "Supported · 2 runs · viability 92% → 81%"
    assert_includes draft, "- Held at 4C [F2]"
    assert_includes draft, "- It failed [F3]"
    assert_includes draft, "Not run: Idle A, Idle B"
    assert_match(/## General\n- General thing \[F1\]/, draft)
    refute_includes draft, "## Idle"
  end

  test "report markdown has conclusion, numbered findings and a tests table" do
    @project.update!(conclusion: "It holds.")
    t = @project.create_test!(name: "Fridge | 4C")
    t.update!(verdict: "supported")
    t.add_finding!("Held")
    t.create_run!(date: "2026-10-06", result: "ok")
    md = kb_report_markdown(@project)
    assert_includes md, "# Ferment"
    assert_includes md, "## Conclusion\n\nIt holds."
    assert_includes md, "- **F1** Held"
    assert_includes md, "| Fridge \\| 4C | - | supported | 1 | 2026-10-06 | ok |"
  end

  test "short ages" do
    now = Time.utc(2026, 10, 20, 12)
    assert_equal "now", kb_short_age(now - 20, now: now)
    assert_equal "5m", kb_short_age(now - 300, now: now)
    assert_equal "3h", kb_short_age(now - 3 * 3600, now: now)
    assert_equal "2d", kb_short_age(now - 2 * 86_400, now: now)
    assert_equal "2w", kb_short_age(now - 15 * 86_400, now: now)
  end
end
