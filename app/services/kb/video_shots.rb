require "fileutils"

module Kb
  # Frame captures live in a sibling folder named like the video ("clip.mp4" -> "clip/"),
  # as "clip — 01m23.4s.png" (+ " 2", " 3"... on collisions; older "01m23s" names still read).
  # The timestamp in the name is the source of truth for seeking, so dropped-in shots work too.
  module VideoShots
    class Blocked < StandardError; end

    NAME = /— (\d+)m(\d{2}(?:\.\d)?)s(?: (\d+))?\.(?:png|jpe?g)\z/i
    LIMIT = 200

    module_function

    def dir(video) = File.join(File.dirname(video), File.basename(video, File.extname(video)))

    # Next free target path for a capture at `seconds`; creates the folder.
    def next_path(video, seconds)
      folder = dir(video)
      raise Blocked, "A file named \"#{File.basename(folder)}\" blocks the screenshots folder." if File.exist?(folder) && !File.directory?(folder)

      FileUtils.mkdir_p(folder)
      tenths = (seconds * 10).floor
      base = File.join(folder, format("%s — %02dm%02d.%ds", File.basename(folder), tenths / 600, tenths % 600 / 10, tenths % 10))
      path = "#{base}.png"
      number = 1
      path = "#{base} #{number += 1}.png" while File.exist?(path)
      path
    end

    # Tree label: "clip — 00m02.3s.png" inside "clip/" shows just "00m02.3s.png".
    def label(name, folder)
      prefix = "#{folder} — "
      name.start_with?(prefix) && NAME.match?(name) ? name.delete_prefix(prefix) : name
    end

    def time_of(name)
      (m = NAME.match(name)) && (m[1].to_i * 60) + m[2].to_f
    end

    # Callers move the video, then call this: frames move into the video's new folder (merged
    # if it exists) and take the new video name. Never overwrites: collisions get " 2", " 3"...
    def carry!(from, to)
      old = dir(from)
      new = dir(to)
      return if old == new || !File.directory?(old) || (File.exist?(new) && !File.directory?(new))

      FileUtils.mkdir_p(new)
      prefix = "#{File.basename(old)} —"
      Dir.children(old).each do |n|
        renamed = n.start_with?(prefix) && NAME.match?(n) ? n.sub(prefix, "#{File.basename(new)} —") : n
        File.rename(File.join(old, n), free(new, renamed))
      end
      Dir.rmdir(old)
    rescue Errno::ENOTEMPTY
      nil
    end

    # `name` inside `folder`, or the next free " N" variant (before the extension).
    def free(folder, name)
      path = File.join(folder, name)
      return path unless File.exist?(path)

      base = name.sub(/(?: \d+)?(\.\w+)?\z/, "")
      ext = File.extname(name)
      number = 1
      path = File.join(folder, "#{base} #{number += 1}#{ext}") while File.exist?(path) && number < 10_000
      path
    end

    # [[file name, seconds], ...] oldest moment first.
    def list(video)
      Dir.children(dir(video)).filter_map { |n| (t = time_of(n)) && [ n, t, NAME.match(n)[3].to_i ] }
         .sort_by { |n, t, k| [ t, k, n ] }.first(LIMIT).map { |n, t, _| [ n, t ] }
    rescue Errno::ENOENT, Errno::ENOTDIR
      []
    end
  end
end
