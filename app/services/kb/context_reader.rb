module Kb
  class ContextReader
    MAX_BYTES = 160.kilobytes
    MAX_FILES = 120
    TEXT_EXTENSIONS = %w[.md .txt .text .csv .json .yml .yaml .xml .html .htm .rb .js .ts .tsx .jsx .css .scss .py .sh].freeze

    def initialize(base:, relative_path:, kind:)
      @base = File.expand_path(base)
      @relative_path = relative_path.to_s
      @kind = kind.to_s
    end

    def call
      path = safe_path
      raise ArgumentError, "Selected KB context is no longer available" unless path

      kind == "folder" ? read_folder(path) : read_file(path)
    end

    private

    attr_reader :base, :relative_path, :kind

    def safe_path
      absolute = File.expand_path(File.join(base, relative_path))
      return nil unless absolute.start_with?("#{base}/") || absolute == base
      return nil if symlink_in_path?(absolute)
      return nil unless kind == "folder" ? File.directory?(absolute) : File.file?(absolute)

      absolute
    end

    def read_folder(folder)
      paths = Dir.glob(File.join(folder, "**", "*"), File::FNM_DOTMATCH)
                 .reject { |path| File.symlink?(path) || hidden_path?(path.delete_prefix("#{folder}/")) }
                 .select { |path| File.file?(path) }
                 .sort
                 .first(MAX_FILES)

      sections = ["Folder: #{relative_path}", "Files:"]
      sections.concat(paths.map { |path| "- #{path.delete_prefix("#{folder}/")}" })
      remaining = MAX_BYTES

      paths.each do |path|
        next unless text_file?(path)
        break if remaining <= 0

        body = read_limited(path, remaining)
        remaining -= body.bytesize
        sections << "\n## #{path.delete_prefix("#{folder}/")}\n\n#{body}"
      end
      sections.join("\n")
    end

    def read_file(path)
      stat = File.stat(path)
      header = "File: #{relative_path}\nSize: #{stat.size} bytes\nModified: #{stat.mtime.iso8601}"
      return header unless text_file?(path)

      "#{header}\n\nContents:\n#{read_limited(path, MAX_BYTES)}"
    end

    def text_file?(path)
      TEXT_EXTENSIONS.include?(File.extname(path).downcase)
    end

    def read_limited(path, limit)
      File.open(path, "rb") { |file| file.read(limit).to_s.encode("UTF-8", invalid: :replace, undef: :replace) }
    end

    def hidden_path?(relative_path)
      relative_path.split(File::SEPARATOR).any? { |segment| segment.start_with?(".") }
    end

    def symlink_in_path?(absolute)
      current = base
      absolute.delete_prefix(base).delete_prefix("/").split("/").any? do |segment|
        current = File.join(current, segment)
        File.symlink?(current)
      end
    end
  end
end
