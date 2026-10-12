require "yaml"
require "securerandom"

module Kb
  # Shared base for folders backed by a hidden YAML dotfile (project/test/run).
  # Disk is the source of truth; every path stays inside `base`.
  class YamlNode
    attr_reader :base, :rel

    # Same rules as KbController#valid_node_name?.
    def self.valid_name?(name)
      name.present? && name.length <= 255 && !name.start_with?(".") && name.match?(%r{\A[^/\\\0]+\z})
    end

    # Absolute path for rel inside base, or nil on traversal / symlink escape.
    def self.safe_abs(base, rel)
      base = File.expand_path(base)
      abs = File.expand_path(File.join(base, rel.to_s))
      return nil unless abs == base || abs.start_with?("#{base}/")

      current = base
      abs.delete_prefix(base).delete_prefix("/").split("/").each do |segment|
        current = File.join(current, segment)
        return nil if File.symlink?(current)
      end
      abs
    end

    # Malformed, missing or non-hash YAML reads as {}.
    def self.read_meta(path)
      data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: false)
      data.is_a?(Hash) ? data : {}
    rescue StandardError
      {}
    end

    # Creates a child folder of parent_abs; raises ArgumentError on bad/duplicate name.
    def self.make_dir!(parent_abs, name)
      raise ArgumentError, "Invalid name." unless valid_name?(name)

      abs = File.join(parent_abs, name)
      raise ArgumentError, "\"#{name}\" already exists." if File.exist?(abs)

      Dir.mkdir(abs)
      abs
    end

    def initialize(base, rel)
      @base = File.expand_path(base)
      @rel = rel.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    end

    def name = File.basename(rel)
    def abs = self.class.safe_abs(base, rel)
    def id = meta["id"]
    def created_at = meta["created_at"]

    def update!(attrs)
      data = meta.merge(attrs.to_h.stringify_keys.slice(*self.class::FIELDS))
      write_meta!(data)
      @meta = nil
      self
    end

    private

    def meta
      @meta ||= self.class.read_meta(File.join(abs, self.class::META_FILE))
    end

    def write_meta!(data)
      path = File.join(abs, self.class::META_FILE)
      tmp = "#{path}.#{SecureRandom.hex(4)}.tmp"
      File.write(tmp, YAML.dump(data))
      File.rename(tmp, path)
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end

    def self.new_meta(extra)
      { "id" => SecureRandom.uuid }.merge(extra).merge("created_at" => Time.now.utc)
    end

    def child_dirs(dir)
      return [] unless dir && File.directory?(dir)

      Dir.children(dir).sort.select { |c| !c.start_with?(".") && File.directory?(File.join(dir, c)) && !File.symlink?(File.join(dir, c)) }
    end
  end
end
