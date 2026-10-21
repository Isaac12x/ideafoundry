require "rubygems/package"
require "zip"
require "zlib"

module Kb
  # Read-only peek into zip / 7z / rar / tar(.gz) archives (and cbz-style comics): list entries, stream
  # ONE entry into memory. Nothing is ever extracted to disk, so there is no zip-slip surface; entry names
  # are only ever matched against the listing, never joined into a path. Caps bound the work done per request.
  module Archive
    MAX_ENTRIES = 5_000
    ENTRY_CAP = 50.megabytes
    TIMEOUT = 30
    ZIP_EXTENSIONS = %w[.zip .cbz .f3d .f3z].freeze
    SEVEN_ZIP_EXTENSIONS = %w[.7z .cb7 .rar .cbr].freeze
    TAR_EXTENSIONS = %w[.tar .cbt].freeze
    PAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .avif .bmp].freeze # svg never counts as a comic page

    class Error < StandardError; end
    class MissingTool < Error; end
    class NotFound < Error; end
    class TooLarge < Error; end

    Entry = Struct.new(:path, :size, :mtime, :dir, keyword_init: true)
    Listing = Struct.new(:entries, :truncated, keyword_init: true) do
      def files = entries.reject(&:dir)
      def total_size = files.sum { |entry| entry.size.to_i }
    end

    module_function

    def seven_zip = %w[7z 7zz 7za].filter_map { |name| LocalTool.path(name, env: "SEVEN_ZIP_BIN") }.first

    def format_for(abs)
      name = abs.to_s.downcase
      ext = File.extname(name)
      return :tar_gz if name.end_with?(".tar.gz") || ext == ".tgz"
      return :zip if ZIP_EXTENSIONS.include?(ext)
      return :seven_zip if SEVEN_ZIP_EXTENSIONS.include?(ext)

      :tar if TAR_EXTENSIONS.include?(ext)
    end

    def list(abs)
      format = format_for(abs) or raise Error, "Unsupported archive type."
      entries = case format
      when :zip then list_zip(abs)
      when :seven_zip then list_seven_zip(abs)
      else list_tar(abs, gzip: format == :tar_gz)
      end
      Listing.new(entries: entries.first(MAX_ENTRIES), truncated: entries.size > MAX_ENTRIES)
    rescue Zip::Error, Zlib::Error, Gem::Package::Error, SystemCallError => e
      raise Error, "Could not read this archive (#{e.message.truncate(120)})."
    rescue Subprocess::Timeout => e
      raise Error, e.message
    end

    # Bytes of one file entry (matched by exact listed name), at most `cap`.
    def read_entry(abs, name, cap: ENTRY_CAP)
      entry = list(abs).files.find { |candidate| candidate.path == name } or raise NotFound, "No such file in the archive."
      raise TooLarge, "Entry is larger than #{cap / 1.megabyte} MB." if entry.size.to_i > cap

      format = format_for(abs)
      data = case format
      when :zip then read_zip(abs, name, cap)
      when :seven_zip then read_seven_zip(abs, name)
      else read_tar(abs, name, cap, gzip: format == :tar_gz)
      end
      raise TooLarge, "Entry is larger than #{cap / 1.megabyte} MB." if data.bytesize > cap

      data
    rescue Zip::Error, Zlib::Error, Gem::Package::Error, SystemCallError => e
      raise Error, "Could not read this entry (#{e.message.truncate(120)})."
    rescue Subprocess::Timeout => e
      raise Error, e.message
    end

    # Image entries of a comic, in reading order.
    def pages(listing)
      listing.files
             .select { |entry| PAGE_EXTENSIONS.include?(File.extname(entry.path).downcase) && !File.basename(entry.path).start_with?(".") && !entry.path.start_with?("__MACOSX/") }
             .sort_by { |entry| natural_key(entry.path) }
    end

    # { "name" => { dir: true, children: {...} } | { entry: Entry } }, folders first, natural order.
    def tree(entries)
      root = {}
      entries.each do |entry|
        *dirs, leaf = entry.path.split("/").reject(&:empty?)
        next unless leaf

        level = dirs.inject(root) { |node, segment| folder_node(node, segment)[:children] }
        entry.dir ? folder_node(level, leaf) : level[leaf] = { entry: entry }
      end
      sort_tree(root)
    end

    def folder_node(level, name) = level[name]&.key?(:children) ? level[name] : (level[name] = { dir: true, children: {} })

    def natural_key(name) = name.downcase.scan(/\d+|\D+/).map { |part| part.match?(/\A\d/) ? [ 0, part.to_i, "" ] : [ 1, 0, part ] }

    def sort_tree(level)
      level.sort_by { |name, node| [ node[:dir] ? 0 : 1, natural_key(name) ] }.to_h.tap do |sorted|
        sorted.each_value { |node| node[:children] = sort_tree(node[:children]) if node[:dir] }
      end
    end

    def safe_name?(name) = name.present? && !name.include?("\0") && !name.start_with?("/") && name.split("/").none? { |segment| segment == ".." }

    def list_zip(abs)
      out = []
      Zip::File.open(abs) do |zip|
        zip.each do |entry|
          next unless safe_name?(entry.name) && !entry.symlink?

          out << Entry.new(path: entry.name.chomp("/"), size: entry.size, mtime: entry.time, dir: entry.directory?)
          break if out.size > MAX_ENTRIES
        end
      end
      out
    end

    def read_zip(abs, name, cap)
      Zip::File.open(abs) do |zip|
        entry = zip.find_entry(name) or raise NotFound, "No such file in the archive."
        entry.get_input_stream { |io| io.read(cap + 1).to_s }
      end
    end

    def list_tar(abs, gzip:)
      out = []
      each_tar(abs, gzip) do |entry|
        name = entry.full_name.sub(%r{\A\./}, "")
        next unless safe_name?(name) && (entry.file? || entry.directory?)

        out << Entry.new(path: name.chomp("/"), size: entry.header.size, mtime: entry.header.mtime, dir: entry.directory?)
        break if out.size > MAX_ENTRIES
      end
      out
    end

    def read_tar(abs, name, cap, gzip:)
      each_tar(abs, gzip) do |entry|
        return entry.read(cap + 1).to_s if entry.file? && entry.full_name.sub(%r{\A\./}, "") == name
      end
      raise NotFound, "No such file in the archive."
    end

    # Streams a (gzipped) tar under a wall-clock limit; `break` in the block stops early.
    def each_tar(abs, gzip, &block)
      ::Timeout.timeout(TIMEOUT) do
        File.open(abs, "rb") do |file|
          io = gzip ? Zlib::GzipReader.new(file) : file
          Gem::Package::TarReader.new(io) { |reader| reader.each(&block) }
        end
      end
    rescue ::Timeout::Error
      raise Error, "Reading took longer than #{TIMEOUT}s."
    end

    def list_seven_zip(abs)
      out, err, status = Subprocess.capture(require_seven_zip, "l", "-slt", "-ba", "-sccUTF-8", "-spd", "--", abs, timeout: TIMEOUT)
      raise Error, err.to_s.lines.map(&:strip).reject(&:empty?).last.to_s.truncate(160).presence || "7z could not list this archive." unless status.success?

      out.force_encoding(Encoding::UTF_8).scrub.split(/\r?\n\r?\n/).filter_map do |block|
        fields = block.lines.filter_map { |line| line.chomp.split(" = ", 2) if line.include?(" = ") }.to_h
        name = fields["Path"].to_s.tr("\\", "/")
        next unless safe_name?(name) && !fields["Attributes"].to_s.start_with?("l")

        dir = fields["Folder"] == "+" || fields["Attributes"].to_s.start_with?("D")
        Entry.new(path: name.chomp("/"), size: dir ? 0 : fields["Size"].to_i, mtime: parse_time(fields["Modified"]), dir: dir)
      end
    end

    def read_seven_zip(abs, name)
      out, err, status = Subprocess.capture(require_seven_zip, "e", "-so", "-spd", "-sccUTF-8", "--", abs, name, timeout: TIMEOUT)
      raise Error, err.to_s.lines.last.to_s.strip.truncate(160).presence || "7z could not read this entry." unless status.success?

      out
    end

    def require_seven_zip
      seven_zip || raise(MissingTool, "7z is not installed. Install it with `brew install 7zip` (or set SEVEN_ZIP_BIN).")
    end

    def parse_time(value) = (Time.zone.parse(value.to_s) if value.present?)
  end
end
