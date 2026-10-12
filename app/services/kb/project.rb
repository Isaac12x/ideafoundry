module Kb
  # A KB folder marked with .kb-project.yml. Holds research entries + Tests/.
  class Project < YamlNode
    META_FILE = ".kb-project.yml".freeze
    FIELDS = %w[goal status private conclusion].freeze
    STATUSES = %w[active paused concluded].freeze
    TESTS_DIR = "Tests".freeze

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

      def create!(base:, parent_rel:, name:, goal: "", private: true)
        parent = safe_abs(base, parent_rel)
        raise ArgumentError, "Parent folder not found." unless parent && File.directory?(parent)

        abs = make_dir!(parent, name)
        project = new(base, File.join(parent_rel.to_s, name))
        project.send(:write_meta!, new_meta("goal" => goal.to_s, "status" => "active",
                                            "private" => cast_bool(private), "conclusion" => ""))
        project
      rescue StandardError
        FileUtils.rm_rf(abs) if abs && !File.exist?(File.join(abs, META_FILE))
        raise
      end

      # Marks an existing folder as a project in place (no-op if already one).
      def convert!(base:, rel:, private: true)
        abs = safe_abs(base, rel)
        raise ArgumentError, "Folder not found." unless abs && rel.to_s.present? && File.directory?(abs)

        project = new(base, rel)
        unless File.file?(File.join(abs, META_FILE))
          project.send(:write_meta!, new_meta("goal" => "", "status" => "active",
                                              "private" => cast_bool(private), "conclusion" => ""))
        end
        project
      end

      def cast_bool(value)
        ActiveModel::Type::Boolean.new.cast(value) ? true : false
      end
    end

    def goal = meta["goal"].to_s
    def conclusion = meta["conclusion"].to_s
    def status = STATUSES.include?(meta["status"]) ? meta["status"] : "active"
    # ponytail: missing/malformed => private (fail closed)
    def private? = meta["private"] == false ? false : true

    def update!(attrs)
      attrs = attrs.to_h.stringify_keys
      if attrs.key?("status") && !STATUSES.include?(attrs["status"].to_s)
        raise ArgumentError, "Invalid status."
      end
      attrs["private"] = self.class.cast_bool(attrs["private"]) if attrs.key?("private")
      super(attrs)
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

    def tests_abs
      dir = File.join(abs, TESTS_DIR)
      File.symlink?(dir) ? nil : dir
    end
  end
end
