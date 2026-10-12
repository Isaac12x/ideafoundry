module Kb
  # One conduct of a test on a date: <test>/<YYYY-MM-DD[ (n)]>/.
  class TestRun < YamlNode
    META_FILE = ".kb-run.yml".freeze
    FIELDS = %w[date conditions result measurements].freeze

    attr_reader :test

    def self.normalize_measurements(list)
      Array(list).filter_map do |m|
        m = m.to_h.stringify_keys
        next if m["name"].to_s.strip.empty?

        { "name" => m["name"].to_s.strip, "value" => m["value"].to_s, "unit" => m["unit"].to_s }
      end
    end

    def initialize(base, rel, test = nil)
      super(base, rel)
      @test = test
    end

    # Metadata date, else parsed from the folder name; nil if neither.
    def date
      value = meta["date"]
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

      Date.parse(value.to_s.presence || name[/\A\d{4}-\d{2}-\d{2}/].to_s)
    rescue ArgumentError
      nil
    end

    def conditions = meta["conditions"].to_s
    def result = meta["result"].to_s
    def measurements = self.class.normalize_measurements(meta["measurements"])

    # Entries in the run folder except dotfiles (names).
    def files
      return [] unless abs && File.directory?(abs)

      Dir.children(abs).reject { |c| c.start_with?(".") || File.symlink?(File.join(abs, c)) }.sort
    end

    def update!(attrs)
      attrs = attrs.to_h.stringify_keys
      attrs["measurements"] = self.class.normalize_measurements(attrs["measurements"]) if attrs.key?("measurements")
      attrs["date"] = Date.parse(attrs["date"].to_s) if attrs.key?("date")
      super(attrs)
    end
  end
end
