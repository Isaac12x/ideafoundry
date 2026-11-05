require "fileutils"

module Kb
  # "Why I saved this": a markdown note paired with any non-markdown KB file. Like the
  # transcript .vtt, the source of truth is a sidecar next to the file, "<filename>.note.md"
  # (clip.mp4 -> clip.mp4.note.md), so it works for dropped-in files, shows in Finder, and
  # survives DB loss. The tree hides it and marks the file instead.
  module Note
    SUFFIX = ".note.md".freeze
    MAX_BYTES = 64.kilobytes

    module_function

    def sidecar(abs) = "#{abs}#{SUFFIX}"

    def sidecar?(path) = path.to_s.end_with?(SUFFIX)

    # Notes pair with anything that is not itself markdown/a note.
    def eligible?(abs) = !sidecar?(abs) && Kb::MediaTypes.kind_for(abs) != :markdown

    # Sidecar path when `abs` has a note next to it, else nil.
    def sidecar_for(abs)
      side = sidecar(abs)
      side if eligible?(abs) && File.file?(side) && !File.symlink?(side)
    end

    def read(abs)
      side = sidecar_for(abs)
      side ? File.read(side) : ""
    end

    # First line of the note (<=120 chars) for the tree tooltip; reads only the head of the sidecar.
    def preview(abs)
      return unless (side = sidecar_for(abs))

      head = File.open(side) { |f| f.read(1024) }.to_s.scrub
      line = head.lines.map { |l| l.delete("*_`").sub(/\A(?:#+|>|[-+])\s+/, "").strip }.find(&:present?)
      line ? Kb::MarkdownRenderer::ARROWS.reduce(line) { |t, (re, glyph)| t.gsub(re, glyph) }.truncate(120) : "Note"
    end

    # Blank text removes the sidecar. Returns the stored text.
    def write!(abs, text)
      text = text.to_s.strip
      raise ArgumentError, "Note is too long." if text.bytesize > MAX_BYTES

      side = sidecar(abs)
      if text.empty?
        FileUtils.rm_f(side)
        return ""
      end

      tmp = "#{side}.tmp"
      raise ArgumentError, "Note path is a symlink." if File.symlink?(side) || File.symlink?(tmp)

      File.write(tmp, "#{text}\n")
      File.rename(tmp, side)
      text
    end

    # Callers grab `side = sidecar_for(from)` before moving the media, then call this after.
    def carry!(side, to)
      FileUtils.mv(side, sidecar(to)) if side && !File.exist?(sidecar(to))
    end
  end
end
