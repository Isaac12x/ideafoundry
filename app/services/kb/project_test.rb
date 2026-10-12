module Kb
  # A real-world experiment inside <project>/Tests/<name>/, run repeatedly.
  class ProjectTest < YamlNode
    META_FILE = ".kb-test.yml".freeze
    FIELDS = %w[objective protocol].freeze
    DATE_NAME = /\A\d{4}-\d{2}-\d{2}/

    attr_reader :project

    def initialize(base, rel, project = nil)
      super(base, rel)
      @project = project
    end

    def objective = meta["objective"].to_s
    def protocol = meta["protocol"].to_s

    # Date-named folders (or any folder with a run marker), oldest first.
    def runs
      child_dirs(abs).select { |n| n.match?(DATE_NAME) || File.file?(File.join(abs, n, TestRun::META_FILE)) }
                     .map { |n| TestRun.new(base, File.join(rel, n), self) }
                     .sort_by { |r| [r.date.to_s, r.name] }
    end

    def create_run!(date: Date.current, conditions: "", result: "", measurements: [])
      date = Date.parse(date.to_s)
      name = date.iso8601
      n = 1
      name = "#{date.iso8601} (#{n += 1})" while File.exist?(File.join(abs, name))
      self.class.make_dir!(abs, name)
      run = TestRun.new(base, File.join(rel, name), self)
      run.send(:write_meta!, self.class.new_meta("date" => date, "conditions" => conditions.to_s, "result" => result.to_s,
                                                  "measurements" => TestRun.normalize_measurements(measurements)))
      run
    end
  end
end
