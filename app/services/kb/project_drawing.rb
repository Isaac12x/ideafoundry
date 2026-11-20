require "base64"

module Kb
  # Excalidraw drawings inserted into project text. Source of truth is a pair of hidden files inside the project
  # folder (so they move, lock and back up with it): `.drawings/<id>.excalidraw` (editable scene JSON) and
  # `.drawings/<id>.png` (what the text shows). Same JSON shape the idea drawings use.
  class ProjectDrawing
    DIR = ".drawings".freeze
    ID = /\A[0-9a-f]{8}\z/
    PNG_URL = %r{\Adata:image/png;base64,([A-Za-z0-9+/=\s]+)\z}
    MAX_BYTES = 12.megabytes

    attr_reader :id

    def initialize(project, id)
      raise ArgumentError, "Invalid drawing." unless id.to_s.match?(ID)

      @project = project
      @id = id.to_s
    end

    def self.create!(project, **attrs) = new(project, SecureRandom.hex(4)).tap { |d| d.write!(**attrs) }

    def exist? = File.file?(path("excalidraw"))
    def png? = File.file?(path("png"))
    def png_path = path("png")

    def title = scene["title"].presence || "Untitled"
    def content = scene["content"] || {}

    def write!(title:, content:, png_data_url: nil)
      raise ArgumentError, "Drawing is too large." if content.to_json.bytesize > MAX_BYTES

      FileUtils.mkdir_p(File.dirname(path("excalidraw")))
      File.write(path("excalidraw"), JSON.generate("title" => title.to_s.first(120), "content" => content))
      return unless (png = png_data_url.to_s[PNG_URL, 1])

      File.binwrite(path("png"), Base64.decode64(png).byteslice(0, MAX_BYTES))
    end

    private

    def scene
      @scene ||= JSON.parse(File.read(path("excalidraw")))
    rescue StandardError
      {}
    end

    def path(ext)
      base = Kb::YamlNode.safe_abs(@project.base, File.join(@project.rel, DIR)) or raise ArgumentError, "Invalid drawing."
      File.join(base, "#{@id}.#{ext}")
    end
  end
end
