# Presentation logic for the KB project page: test ordering, next actions,
# brief checklist, conclusion draft. Views stay declarative.
module KbProjectHelper
  BRIEF_PROMPTS = [
    [ :question, "Question", "What exactly do you want to find out? One sentence." ],
    [ :scope, "Scope", "What is in, what is out, and the limits." ],
    [ :answer, "What counts as an answer", "The result that would settle it: a number, a threshold, a comparison." ]
  ].freeze
  BRIEF_TEMPLATE = "## Question\n\n\n## Scope\n\n\n## What counts as an answer\n\n".freeze
  TONES = { "open" => "muted", "supported" => "success", "refuted" => "danger", "inconclusive" => "warning" }.freeze

  def kb_verdict_tone(verdict) = TONES[verdict]

  # :file | :project | :dir | :missing for a build-plan item link (a KB rel path).
  def kb_build_link_kind(project, rel)
    abs = Kb::YamlNode.safe_abs(project.base, rel)
    return :missing unless abs && File.exist?(abs)
    return :file if File.file?(abs)

    Kb::Project.at(project.base, rel) ? :project : :dir
  end

  # Stable DOM id, so jump links survive reordering.
  def kb_test_dom_id(test) = "kbp-test-#{Digest::MD5.hexdigest(test.rel)[0, 8]}"

  def kb_runs(test)
    (@kb_runs ||= {})[test.rel] ||= test.runs
  end

  def kb_last_run_on(test) = kb_runs(test).filter_map(&:date).max

  # Needs-attention order used by the strip and the cards: open verdicts first,
  # then most recently run, then name.
  def kb_attention_tests(project)
    project.tests.sort_by { |t| [ t.verdict == "open" ? 0 : 1, -(kb_last_run_on(t)&.jd || 0), t.name.downcase ] }
  end

  # Cards worth opening in test mode: open verdicts plus the latest-run test;
  # never none.
  def kb_open_test_rels(tests)
    open = tests.select { |t| t.verdict == "open" }.map(&:rel)
    latest = tests.select { |t| kb_last_run_on(t) }.max_by { |t| kb_last_run_on(t) }
    open << latest.rel if latest
    open << tests.first.rel if open.empty? && tests.any?
    open.uniq
  end

  # The report reads in the project's own stage order, then name.
  def kb_results_tests(project)
    stages = project.stages
    project.tests.sort_by { |t| [ stages.index(t.stage) || stages.size, t.name.downcase ] }
  end

  # Up to 3 pending things: [{label:, target:}], target = element id to jump to.
  # In conclude the work is done: only a missing conclusion is a to-do; open
  # tests are a soft warning (kb_unsettled_tests), not a list of chores.
  def kb_project_next(project, entries, mode)
    todo = []
    if mode == "conclude"
      todo << { label: "No conclusion written", target: "kbp-sec-conclusion" } if project.conclusion.blank?
      return todo
    end
    todo << { label: "Brief not written", target: "kbp-sec-brief" } if mode == "frame" && project.brief.blank?
    inbox = entries.count { |e| e[:role].blank? }
    todo << { label: "#{pluralize(inbox, 'file')} to sort", target: "kbp-sec-materials" } if inbox.positive?
    todo << { label: "No findings yet", target: "kbp-sec-findings" } if mode == "research" && project.findings.empty?
    kb_attention_tests(project).each do |t|
      runs = kb_runs(t).size
      if runs.zero?
        todo << { label: "#{t.name}: no runs yet", target: kb_test_dom_id(t) }
      elsif runs >= 2 && t.verdict == "open"
        todo << { label: "#{t.name}: #{pluralize(runs, 'run')}, no verdict", target: kb_test_dom_id(t) }
      end
    end
    todo.first(3)
  end

  # Tests that will read as "open" in the report.
  def kb_unsettled_tests(project) = project.tests.select { |t| t.verdict == "open" }

  # {question: "text", scope: "", answer: ""}: what the brief says under each prompt
  # (a heading or a "Label:" line starts one).
  def kb_brief_sections(brief)
    found = Hash.new("")
    key = nil
    brief.to_s.each_line(chomp: true) do |line|
      if (m = line.match(/\A\s*#+\s*(.+?)\s*\z/))
        key = kb_brief_key(m[1])
      elsif (m = line.match(/\A\s*(question|scope|what counts as an answer|answer|success)\s*:\s*(.*)\z/i))
        key = kb_brief_key(m[1])
        found[key] += "#{m[2]}\n" if key
      elsif key
        found[key] += "#{line}\n"
      end
    end
    BRIEF_PROMPTS.to_h { |k, _, _| [ k, found[k].strip ] }
  end

  # {question: true/false, ...}: a prompt counts when it has text.
  def kb_brief_state(brief) = kb_brief_sections(brief).transform_values(&:present?)

  VERDICT_ORDER = %w[supported refuted inconclusive open].freeze

  # {finding id => n}: the numbering the Summary of findings shows as F1, F2...
  def kb_finding_numbers(project)
    n = 0
    project.all_findings.flat_map { |g| g[:items] }.to_h { |f| [ f["id"], n += 1 ] }
  end

  # "viability 92% → 81%" for up to 2 measurements logged in 2+ runs.
  def kb_measure_moves(runs)
    by_name = runs.flat_map { |r| r.measurements.map { |m| [ m["name"], m ] } }.group_by(&:first)
    by_name.select { |_, list| list.size >= 2 }.first(2).map do |name, list|
      first, last = list.first.last, list.last.last
      fmt = ->(m) { m["unit"].to_s.start_with?("%") ? "#{m['value']}%" : [ m["value"], m["unit"].presence ].compact.join(" ") }
      "#{name} #{fmt.call(first)} → #{fmt.call(last)}"
    end
  end

  # A draft conclusion to edit: question, answer slot, tests by verdict with their
  # key movement and numbered findings, untouched tests in one line, then general findings.
  def kb_conclusion_draft(project)
    numbers = kb_finding_numbers(project)
    goal = project.goal.presence || project.name
    out = [ "# #{goal}", "", "**Answer:** _write the answer in a sentence or two_", "" ]
    tests = project.tests.sort_by { |t| [ VERDICT_ORDER.index(t.verdict) || 9, t.name.downcase ] }
    idle, active = tests.partition { |t| kb_runs(t).empty? && t.findings.empty? }
    active.each do |t|
      runs = kb_runs(t)
      facts = [ t.verdict.capitalize, pluralize(runs.size, "run"), *kb_measure_moves(runs) ]
      out << "## #{t.name}"
      out << facts.join(" · ")
      out << ""
      t.findings.each { |f| out << "- #{f['text'].squish} [F#{numbers[f['id']]}]" }
      out << "" if t.findings.any?
    end
    out << "Not run: #{idle.map(&:name).join(', ')}" << "" if idle.any?
    general = project.findings
    if general.any?
      out << "## General"
      general.each { |f| out << "- #{f['text'].squish} [F#{numbers[f['id']]}]" }
      out << ""
    end
    out.join("\n").strip + "\n"
  end

  # The whole report as markdown, for "Copy as markdown".
  def kb_report_markdown(project)
    cell = ->(text) { text.to_s.gsub("|", "\\|").squish }
    numbers = kb_finding_numbers(project)
    out = [ "# #{project.name}", "" ]
    out << "> #{project.goal}" << "" if project.goal.present?
    out << "Concluded #{project.concluded_on.strftime('%-d %B %Y')}" << "" if project.status == "concluded" && project.concluded_on
    out << "## Conclusion" << "" << (project.conclusion.presence || "_Not written._") << ""
    out << "## Summary of findings" << ""
    groups = project.all_findings
    if groups.empty?
      out << "_None recorded._" << ""
    else
      groups.each do |g|
        owner = g[:owner]
        out << (owner.is_a?(Kb::ProjectTest) ? "### #{owner.name} (#{owner.verdict})" : "### General") << ""
        g[:items].each { |f| out << "- **F#{numbers[f['id']]}** #{f['text'].squish}" }
        out << ""
      end
    end
    out << "## Tests & results" << ""
    tests = kb_results_tests(project)
    if tests.empty?
      out << "_No tests._"
    else
      out << "| Test | Stage | Verdict | Runs | Last run | Latest result |" << "| --- | --- | --- | ---: | --- | --- |"
      tests.each do |t|
        runs = kb_runs(t)
        last = runs.last
        result = last && (last.result.presence || kb_measure_moves(runs).join(", "))
        out << "| #{cell.call(t.name)} | #{cell.call(t.stage.presence || '-')} | #{t.verdict} | #{runs.size} | #{last ? (last.date&.iso8601 || last.name) : '-'} | #{cell.call(result.presence || '-')} |"
      end
    end
    out.join("\n") + "\n"
  end

  # "now", "5m", "3h", "2d", "6w", "4mo", "2y"
  def kb_short_age(time, now: Time.current)
    secs = (now - time).to_i
    return "now" if secs < 60

    { 60 => [ 60, "m" ], 3600 => [ 3600, "h" ], 86_400 => [ 86_400, "d" ], 604_800 => [ 604_800, "w" ], 2_592_000 => [ 2_592_000, "mo" ], 31_536_000 => [ 31_536_000, "y" ] }
      .select { |floor, _| secs >= floor }.max_by(&:first).then { |_, (div, unit)| "#{secs / div}#{unit}" }
  end

  private

  def kb_brief_key(text)
    case text.downcase
    when /question/ then :question
    when /scope/ then :scope
    when /answer|success|counts/ then :answer
    end
  end
end
