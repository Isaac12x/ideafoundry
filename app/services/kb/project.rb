module Kb
  # A KB folder marked with .kb-project.yml. Holds research entries + Tests/.
  # kind "build" (a build plan) has no Tests/ or stages: a goal + checklist of
  # methods to learn (meta["items"]) instead. Missing kind => "research".
  class Project < YamlNode
    include Findings

    META_FILE = ".kb-project.yml".freeze
    FIELDS = %w[goal brief status private conclusion concluded_on stage stages items].freeze
    ROLES = %w[working reference output].freeze
    DEFAULT_STAGES = %w[Frame Research Test Conclude].freeze
    MAX_STAGES = 8
    MAX_STAGE_LEN = 40
    MAX_NOTE = 280
    STATUSES = %w[active paused concluded].freeze
    KINDS = %w[research build].freeze
    ITEM_STATUSES = %w[todo learning known].freeze
    MAX_ITEMS = 100
    MAX_ITEM_TITLE = 120
    MAX_ITEM_LINKS = 20
    MAX_LINK_LEN = 500
    TESTS_DIR = "Tests".freeze
    # First match wins; word-start only ("testing" hits, "contest" doesn't).
    STAGE_MODES = {
      "frame" => /\b(?:frame|defin|scope|question|brief)/,
      "research" => /\b(?:research|read|explor|learn|survey)/,
      "test" => /\b(?:test|experiment|trial|build|prototype|try)/,
      "conclude" => /\b(?:conclu|done|wrap|result|report|decid|ship)/
    }.freeze

    class << self
      # rel is the project folder.
      def at(base, rel)
        abs = safe_abs(base, rel)
        return nil if abs.nil? || rel.to_s.blank? || !File.file?(File.join(abs, META_FILE))

        new(base, rel)
      end

      # Nearest enclosing project (or rel itself), or nil.
      def containing(base, rel)
        parts = rel.to_s.split("/").reject(&:blank?)
        parts.size.downto(1) do |n|
          project = at(base, parts.first(n).join("/"))
          return project if project
        end
        nil
      end

      def create!(base:, parent_rel:, name:, goal: "", private: true, kind: "research")
        parent = safe_abs(base, parent_rel)
        raise ArgumentError, "Parent folder not found." unless parent && File.directory?(parent)

        abs = make_dir!(parent, name)
        project = new(base, File.join(parent_rel.to_s, name))
        project.send(:write_meta!, new_meta("goal" => goal.to_s, "status" => "active",
                                            "private" => cast_bool(private), "conclusion" => "", **kind_meta(kind)))
        project
      rescue StandardError
        FileUtils.rm_rf(abs) if abs && !File.exist?(File.join(abs, META_FILE))
        raise
      end

      # Marks an existing folder as a project in place (no-op if already one).
      def convert!(base:, rel:, private: true, kind: "research")
        abs = safe_abs(base, rel)
        raise ArgumentError, "Folder not found." unless abs && rel.to_s.present? && File.directory?(abs)

        project = new(base, rel)
        unless File.file?(File.join(abs, META_FILE))
          project.send(:write_meta!, new_meta("goal" => "", "status" => "active",
                                              "private" => cast_bool(private), "conclusion" => "", **kind_meta(kind)))
        end
        project
      end

      # Array or newline-separated String -> clean unique list (<= MAX_STAGES).
      def normalize_stages(value)
        items = value.is_a?(String) ? value.split("\n") : Array(value)
        items.map { |s| s.to_s.strip }.reject { |s| s.blank? || s.length > MAX_STAGE_LEN }
             .uniq(&:downcase).first(MAX_STAGES)
      end

      # Research stays unmarked so existing project files and new ones look alike.
      def kind_meta(kind)
        kind.to_s == "build" ? { "kind" => "build", "items" => [] } : {}
      end

      def cast_bool(value)
        ActiveModel::Type::Boolean.new.cast(value) ? true : false
      end
    end

    def kind = KINDS.include?(meta["kind"]) ? meta["kind"] : "research"
    def build? = kind == "build"

    # Tolerant read: [{ "id", "title", "note", "status", "links" }].
    def items
      Array(meta["items"]).filter_map do |item|
        next unless item.is_a?(Hash) && item["title"].to_s.present?

        { "id" => item["id"].to_s, "title" => item["title"].to_s, "note" => item["note"].to_s,
          "status" => ITEM_STATUSES.include?(item["status"]) ? item["status"] : "todo",
          "links" => Array(item["links"]).map(&:to_s) }
      end
    end

    # [known, total]
    def progress = [ items.count { |i| i["status"] == "known" }, items.size ]

    # Strict write-side cleanup of the checklist (JSON string or array). Blank titles drop out.
    def normalize_items(value)
      list = value.is_a?(String) ? parse_items(value) : value
      raise ArgumentError, "Invalid checklist." unless list.is_a?(Array)
      raise ArgumentError, "Too many items (max #{MAX_ITEMS})." if list.size > MAX_ITEMS

      seen = {}
      list.filter_map do |raw|
        raise ArgumentError, "Invalid checklist." unless raw.is_a?(Hash)

        title = raw["title"].to_s.strip
        next if title.blank?

        status = raw["status"].presence || "todo"
        raise ArgumentError, "Title is too long (max #{MAX_ITEM_TITLE})." if title.length > MAX_ITEM_TITLE
        raise ArgumentError, "Invalid item status." unless ITEM_STATUSES.include?(status)

        note = raw["note"].to_s.strip
        raise ArgumentError, "Note is too long (max #{MAX_NOTE})." if note.length > MAX_NOTE

        id = raw["id"].to_s
        id = SecureRandom.uuid unless id.match?(/\A[0-9a-f-]{8,36}\z/) && !seen[id]
        seen[id] = true
        { "id" => id, "title" => title, "note" => note, "status" => status, "links" => normalize_links(raw["links"]) }
      end
    end

    def goal = meta["goal"].to_s
    def conclusion = meta["conclusion"].to_s
    def brief = meta["brief"].to_s

    def concluded_on
      value = meta["concluded_on"]
      value.is_a?(Date) ? value : Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
    def status = STATUSES.include?(meta["status"]) ? meta["status"] : "active"
    # ponytail: missing/malformed => private (fail closed)
    def private? = locked? || meta["private"] != false
    # Stub marker + encrypted archive on disk; see Kb::ProjectLock.
    def locked? = meta["locked"] == true
    def archive_file = File.basename(meta["archive"].to_s)

    # Falls back to the defaults when missing/invalid.
    def stages
      list = self.class.normalize_stages(meta["stages"])
      list.presence || DEFAULT_STAGES
    end

    def stage
      stages.include?(meta["stage"]) ? meta["stage"] : stages.first
    end

    # "frame" | "research" | "test" | "conclude": drives the page layout.
    def stage_mode(stage = self.stage)
      by_name = STAGE_MODES.find { |_, pattern| stage.to_s.downcase.match?(pattern) }
      return by_name.first if by_name

      index = stages.index(stage)
      return "frame" if index == 0
      index == stages.size - 1 ? "conclude" : "research"
    end

    # Project first, then each test; only owners with findings.
    def all_findings
      ([ self ] + tests).filter_map do |owner|
        items = owner.findings
        { owner: owner, items: items } if items.any?
      end
    end

    def material(name)
      entry = meta["materials"].is_a?(Hash) ? meta["materials"][name.to_s] : nil
      entry = {} unless entry.is_a?(Hash)
      role = ROLES.include?(entry["role"]) ? entry["role"] : nil
      { "role" => role, "stage" => stages.include?(entry["stage"]) ? entry["stage"] : "", "note" => entry["note"].to_s }
    end

    def update!(attrs)
      attrs = attrs.to_h.stringify_keys
      if attrs.key?("items")
        raise ArgumentError, "Only build plans have a checklist." unless build?

        attrs["items"] = normalize_items(attrs["items"])
      end
      if attrs.key?("stages")
        list = self.class.normalize_stages(attrs["stages"])
        raise ArgumentError, "Add at least one valid stage." if list.empty?

        attrs["stages"] = list
        current = attrs.key?("stage") ? attrs["stage"].to_s : meta["stage"]
        attrs["stage"] = list.include?(current) ? current : list.first
      elsif attrs.key?("stage") && !stages.include?(attrs["stage"].to_s)
        raise ArgumentError, "Invalid stage."
      end
      if attrs.key?("status") && !STATUSES.include?(attrs["status"].to_s)
        raise ArgumentError, "Invalid status."
      end
      attrs["private"] = self.class.cast_bool(attrs["private"]) if attrs.key?("private")
      attrs["concluded_on"] = concluded_stamp(attrs["status"]) if attrs.key?("status")
      super(attrs)
    end

    # Only way to write materials (not in FIELDS). All blank drops the key.
    def update_material!(name, role: nil, stage: nil, note: nil)
      raise ArgumentError, "Entry not found." unless material_child?(name)

      role, stage, note = role.to_s, stage.to_s, note.to_s.strip.first(MAX_NOTE)
      raise ArgumentError, "Invalid role." unless role.blank? || ROLES.include?(role)
      raise ArgumentError, "Invalid stage." unless stage.blank? || stages.include?(stage)

      all = materials_hash
      if role.blank? && stage.blank? && note.blank?
        all.delete(name)
      else
        all[name] = { "role" => role, "stage" => stage, "note" => note }
      end
      write_meta!(meta.merge("materials" => all))
      @meta = nil
      self
    end

    # Keeps metadata attached when a direct child is renamed on disk.
    def rename_material!(old, new)
      all = materials_hash
      return self unless all.key?(old.to_s) && self.class.valid_name?(new.to_s)

      all[new.to_s] = all.delete(old.to_s)
      write_meta!(meta.merge("materials" => all))
      @meta = nil
      self
    end

    def tests
      child_dirs(tests_abs).map { |n| ProjectTest.new(base, File.join(rel, TESTS_DIR, n), self) }
    end

    def create_test!(name:, objective: "", protocol: "")
      FileUtils.mkdir_p(tests_abs) unless File.exist?(tests_abs)
      self.class.make_dir!(tests_abs, name)
      test = ProjectTest.new(base, File.join(rel, TESTS_DIR, name), self)
      test.send(:write_meta!, self.class.new_meta("objective" => objective.to_s, "protocol" => protocol.to_s))
      test
    end

    private

    def parse_items(json)
      JSON.parse(json)
    rescue JSON::ParserError
      raise ArgumentError, "Invalid checklist."
    end

    # Array or newline-separated String of KB-relative paths; each must stay inside the source.
    def normalize_links(value)
      list = value.is_a?(String) ? value.split("\n") : Array(value)
      links = list.map { |l| l.to_s.strip }.reject(&:blank?).uniq
      raise ArgumentError, "Too many links on one item (max #{MAX_ITEM_LINKS})." if links.size > MAX_ITEM_LINKS

      links.each do |link|
        safe = link.length <= MAX_LINK_LEN && link.split("/").all? { |seg| self.class.valid_name?(seg) } &&
               self.class.safe_abs(base, link)
        raise ArgumentError, "Link \"#{link.first(60)}\" is not a path inside the KB." unless safe
      end
      links
    end

    # Keeps the original date while concluded; clears it otherwise.
    def concluded_stamp(status)
      return nil unless status.to_s == "concluded"

      meta["concluded_on"].presence || Date.current.iso8601
    end

    def materials_hash
      meta["materials"].is_a?(Hash) ? meta["materials"].dup : {}
    end

    def material_child?(name)
      return false if name.to_s == TESTS_DIR || !self.class.valid_name?(name.to_s)

      path = File.join(abs, name.to_s)
      File.exist?(path) && !File.symlink?(path)
    end

    def tests_abs
      dir = File.join(abs, TESTS_DIR)
      File.symlink?(dir) ? nil : dir
    end
  end
end
