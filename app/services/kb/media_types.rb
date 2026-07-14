module Kb
  module MediaTypes
    MARKDOWN_EXTENSIONS = %w[.md].freeze
    EMBED_EXTENSIONS = %w[.html .htm .docx .xlsx].freeze
    PDF_EXTENSIONS = %w[.pdf].freeze
    IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .webp].freeze
    VIDEO_EXTENSIONS = %w[.mp4 .webm .mov .ogv].freeze
    AUDIO_EXTENSIONS = %w[.mp3 .wav .ogg .m4a .aac .flac].freeze
    LONG_DOC_EXTENSIONS = %w[.tif .tiff].freeze

    MIME_TYPES = {
      ".pdf" => "application/pdf",
      ".mp4" => "video/mp4", ".webm" => "video/webm", ".mov" => "video/quicktime", ".ogv" => "video/ogg",
      ".mp3" => "audio/mpeg", ".wav" => "audio/wav", ".ogg" => "audio/ogg", ".m4a" => "audio/mp4",
      ".aac" => "audio/aac", ".flac" => "audio/flac",
      ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp"
    }.freeze

    module_function

    def kind_for(path)
      extension = File.extname(path).downcase
      return :markdown if MARKDOWN_EXTENSIONS.include?(extension)
      return :embed if EMBED_EXTENSIONS.include?(extension)
      return :pdf if PDF_EXTENSIONS.include?(extension)
      return :image if IMAGE_EXTENSIONS.include?(extension)
      return :video if VIDEO_EXTENSIONS.include?(extension)
      return :audio if AUDIO_EXTENSIONS.include?(extension)
      return :long_doc if LONG_DOC_EXTENSIONS.include?(extension)

      :generic
    end

    def mime_type_for(path)
      MIME_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")
    end
  end
end
