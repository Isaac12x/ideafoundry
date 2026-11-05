module Kb
  module MediaTypes
    MARKDOWN_EXTENSIONS = %w[.md].freeze
    EMBED_EXTENSIONS = %w[.html .htm .docx .pptx .xlsx].freeze
    PDF_EXTENSIONS = %w[.pdf].freeze
    # OCR/extraction only understands these; the other image kinds are view-only.
    OCR_EXTENSIONS = %w[.png .jpg .jpeg .webp].freeze
    # .heic/.heif stay generic: only Safari decodes them.
    IMAGE_EXTENSIONS = (OCR_EXTENSIONS + %w[.gif .svg .avif .bmp .ico]).freeze
    VIDEO_EXTENSIONS = %w[.mp4 .webm .mov .ogv].freeze
    AUDIO_EXTENSIONS = %w[.mp3 .wav .ogg .m4a .aac .flac].freeze
    LONG_DOC_EXTENSIONS = %w[.tif .tiff].freeze
    # Rotatable in the browser: mesh formats via three.js, B-rep CAD via occt-import-js (wasm).
    MESH_EXTENSIONS = %w[.stl .obj .ply .gltf .glb .3mf .fbx .dae].freeze
    BREP_EXTENSIONS = %w[.step .stp .iges .igs .brep].freeze
    MODEL_EXTENSIONS = (MESH_EXTENSIONS + BREP_EXTENSIONS).freeze
    # Proprietary CAD we cannot render: shown with an honest "export it" hint.
    CAD_HINTS = {
      ".f3d" => "Fusion 360 archive. Export as STEP or STL from Fusion (File > Export) to rotate it here.",
      ".f3z" => "Fusion 360 archive. Export as STEP or STL from Fusion (File > Export) to rotate it here.",
      ".sldprt" => "SolidWorks part. Save As STEP or STL in SolidWorks to rotate it here.",
      ".sldasm" => "SolidWorks assembly. Save As STEP or STL in SolidWorks to rotate it here.",
      ".ipt" => "Inventor part. Export as STEP or STL from Inventor to rotate it here.",
      ".iam" => "Inventor assembly. Export as STEP or STL from Inventor to rotate it here.",
      ".blend" => "Blender scene. Export as glTF/GLB, OBJ or STL from Blender (File > Export) to rotate it here."
    }.freeze
    CAD_EXTENSIONS = CAD_HINTS.keys.freeze
    CAD_ZIP_EXTENSIONS = %w[.f3d .f3z].freeze # zip containers; may carry a preview PNG
    ARCHIVE_EXTENSIONS = %w[.zip .7z .rar .tar .tgz].freeze
    ARCHIVE_SUFFIXES = %w[.tar.gz].freeze # File.extname only sees ".gz"
    COMIC_EXTENSIONS = %w[.cbz .cbr .cb7 .cbt].freeze
    EPUB_EXTENSIONS = %w[.epub].freeze
    # Calibre (ebook-convert) turns these into an EPUB sidecar; .djvu goes to PDF via ddjvu.
    # .rb (Rocket eBook) is left out on purpose: it is Ruby source far more often.
    CONVERT_BOOK_EXTENSIONS = %w[.mobi .azw .azw3 .azw4 .kfx .prc .pdb .fb2 .fbz .lit .lrf .tcr .snb .pml .pmlz .chm .txtz .htmlz .ibooks].freeze
    DJVU_EXTENSIONS = %w[.djvu .djv].freeze
    BOOK_EXTENSIONS = (EPUB_EXTENSIONS + CONVERT_BOOK_EXTENSIONS + DJVU_EXTENSIONS).freeze
    # Everything the KB can open beyond text: used to allow creating/renaming to these extensions.
    VIEWER_EXTENSIONS = (MODEL_EXTENSIONS + CAD_EXTENSIONS + ARCHIVE_EXTENSIONS + COMIC_EXTENSIONS + BOOK_EXTENSIONS).freeze

    MIME_TYPES = {
      ".pdf" => "application/pdf",
      ".mp4" => "video/mp4", ".webm" => "video/webm", ".mov" => "video/quicktime", ".ogv" => "video/ogg",
      ".mp3" => "audio/mpeg", ".wav" => "audio/wav", ".ogg" => "audio/ogg", ".m4a" => "audio/mp4",
      ".aac" => "audio/aac", ".flac" => "audio/flac",
      ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp",
      ".gif" => "image/gif", ".svg" => "image/svg+xml", ".avif" => "image/avif", ".bmp" => "image/bmp", ".ico" => "image/x-icon"
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
      return :model if MODEL_EXTENSIONS.include?(extension)
      return :cad if CAD_EXTENSIONS.include?(extension)
      return :comic if COMIC_EXTENSIONS.include?(extension)
      return :book if BOOK_EXTENSIONS.include?(extension)
      return :archive if ARCHIVE_EXTENSIONS.include?(extension) || ARCHIVE_SUFFIXES.any? { |suffix| path.downcase.end_with?(suffix) }

      :generic
    end

    def mime_type_for(path)
      MIME_TYPES.fetch(File.extname(path).downcase, "application/octet-stream")
    end
  end
end
