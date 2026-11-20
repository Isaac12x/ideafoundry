module Kb
  # A real-world experiment inside <project>/Tests/<name>/, run repeatedly.
  class ProjectTest < YamlNode
    include Findings

    META_FILE = ".kb-test.yml".freeze
    FIELDS = %w[objective protocol stage verdict].freeze
    VERDICTS = %w[open supported refuted inconclusive].freeze
    DATE_NAME = /\A\d{4}-\d{2}-\d{2}/

    attr_reader :project

    def initialize(base, rel, project = nil)
      super(base, rel)
      @project = project
    end

    def objective = meta["objective"].to_s
    def protocol = meta["protocol"].to_s
    def stage = project && project.stages.include?(meta["stage"]) ? meta["stage"] : ""

    def verdict = VERDICTS.include?(meta["verdict"]) ? meta["verdict"] : "open"

    def update!(attrs)
      attrs = attrs.to_h.stringify_keys
      stage = attrs["stage"]
      raise ArgumentError, "Invalid verdict." if attrs.key?("verdict") && !VERDICTS.include?(attrs["verdict"].to_s)
      raise ArgumentError, "Invalid stage." if stage.present? && !(project&.stages || []).include?(stage)

      super
    end

    # What the test needs, stored under `requires` (not in FIELDS). Each: {"id","kind","text","at"} plus
    # "url"/"host"/"excerpt" for an imported page. kind: ref (an @token), import (page text kept inline), text.
    def requirements
      Array(meta["requires"]).filter_map do |r|
        next unless r.is_a?(Hash) && r["id"].present? && r["text"].to_s.strip.present?

        r.slice("id", "kind", "text", "at", "url", "host", "excerpt").transform_values(&:to_s)
      end
    end

    # One @-picked reference per token, one import per pasted http(s) link (fetched now, `importer` is stubbed in tests),
    # otherwise the text itself. Returns the new items.
    def add_requirements!(text, importer: Kb::UrlImport)
      text = text.to_s.strip.first(Findings::MAX_FINDING)
      raise ArgumentError, "Requirement can't be blank." if text.blank?

      at = Date.current.iso8601
      refs = Kb::References.parse(text).map { |r| { "kind" => "ref", "text" => r.token } }
      urls = text.gsub(Kb::References::TOKEN, " ").scan(%r{https?://[^\s<>"')]+}).map { |u| u.sub(/[.,;:!?]+\z/, "") }.uniq
      imports = urls.map do |url|
        page = importer.call(url)
        { "kind" => "import", "text" => page["title"].presence || page["host"], "url" => page["url"], "host" => page["host"], "excerpt" => page["excerpt"].to_s }
      rescue Kb::UrlImport::Error => e
        raise ArgumentError, "#{url}: #{e.message}"
      end
      items = refs + imports
      # Free text typed beside tokens/links is a plain note, not dropped.
      note = urls.reduce(text.gsub(Kb::References::TOKEN, " ")) { |t, u| t.gsub(u, " ") }.squish.gsub(/\A[\p{P}\s]+\z/, "").sub(/\s+[.,;:!?]+\z/, "")
      items = [ { "kind" => "text", "text" => items.empty? ? text : note } ] + items if items.empty? || note.present?
      items = items.map { |i| i.merge("id" => SecureRandom.hex(4), "at" => at) }
      write_items!("requires", requirements + items)
      items
    end

    def remove_requirement!(id)
      list = requirements.reject { |r| r["id"] == id.to_s }
      raise ArgumentError, "Requirement not found." if list.size == requirements.size

      write_items!("requires", list)
      self
    end

    # Date-named folders (or any folder with a run marker), oldest first.
    def runs
      child_dirs(abs).select { |n| n.match?(DATE_NAME) || File.file?(File.join(abs, n, TestRun::META_FILE)) }
                     .map { |n| TestRun.new(base, File.join(rel, n), self) }
                     .sort_by { |r| [ r.date.to_s, r.name ] }
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
