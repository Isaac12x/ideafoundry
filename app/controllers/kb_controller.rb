class KbController < ApplicationController
  NATIVE_KB_PATH = KbSource::NATIVE_PATH
  NATIVE_KB_LABEL = KbSource::NATIVE_LABEL
  LAST_DOCUMENT_COOKIE = :kb_last_document

  MARKDOWN_EXTENSIONS   = %w[.md].freeze
  EMBED_EXTENSIONS      = %w[.html .htm .docx .xlsx].freeze
  PDF_EXTENSIONS        = %w[.pdf].freeze
  IMAGE_EXTENSIONS      = %w[.png .jpg .jpeg .webp].freeze
  VIDEO_EXTENSIONS      = %w[.mp4 .webm .mov .ogv].freeze
  AUDIO_EXTENSIONS      = %w[.mp3 .wav .ogg .m4a .aac .flac].freeze
  # TIF/TIFF: not renderable in browsers, extraction only
  LONG_DOC_EXTENSIONS   = %w[.tif .tiff].freeze

  SERVE_EXTENSIONS      = (PDF_EXTENSIONS + IMAGE_EXTENSIONS + VIDEO_EXTENSIONS + AUDIO_EXTENSIONS).freeze
  EXTRACTABLE_EXTENSIONS = (PDF_EXTENSIONS + IMAGE_EXTENSIONS + LONG_DOC_EXTENSIONS).freeze
  KB_EXTENSIONS         = (MARKDOWN_EXTENSIONS + EMBED_EXTENSIONS).freeze
  ALL_EXTENSIONS        = (KB_EXTENSIONS + SERVE_EXTENSIONS + LONG_DOC_EXTENSIONS).freeze

  EMBED_CSP = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:".freeze

  MIME_TYPES = {
    ".pdf"  => "application/pdf",
    ".mp4"  => "video/mp4",
    ".webm" => "video/webm",
    ".mov"  => "video/quicktime",
    ".ogv"  => "video/ogg",
    ".mp3"  => "audio/mpeg",
    ".wav"  => "audio/wav",
    ".ogg"  => "audio/ogg",
    ".m4a"  => "audio/mp4",
    ".aac"  => "audio/aac",
    ".flac" => "audio/flac",
    ".png"  => "image/png",
    ".jpg"  => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".webp" => "image/webp",
  }.freeze

  KbContent = Struct.new(
    :kind, :html, :raw_url, :serve_url, :rel, :src, :filename,
    :created_at, :modified_at,
    :extraction, :output_rel, :mime_type,
    keyword_init: true
  )

  before_action :set_user

  def index
    @folders = build_folder_tree
    @downloads = @user.kb_downloads.active.recent
    @selected_folder_index, @selected_file = initial_document_selection

    @content = render_file(@selected_folder_index, @selected_file)
    remember_document(@selected_folder_index, @selected_file) if displayable_content?(@content)
    @facts = @user.facts.recent
    @maxims = @user.maxims.recent
  end

  def file
    folder_index = params[:src].to_i
    rel_path = params[:file]
    @content = render_file(folder_index, rel_path)
    @selected_file = rel_path
    @selected_folder_index = folder_index
    remember_document(folder_index, rel_path) if displayable_content?(@content)
  end

  def raw
    abs = resolve_kb_path(params[:src].to_i, params[:file], extensions: EMBED_EXTENSIONS)
    return head(:not_found) if abs.nil?

    html = KbDocumentRenderer.new(abs).to_html
    response.set_header("Content-Security-Policy", EMBED_CSP)
    render html: html.html_safe, layout: false, content_type: "text/html"
  rescue KbDocumentRenderer::ConversionError
    head :unprocessable_entity
  end

  def serve
    abs = resolve_kb_path(params[:src].to_i, params[:file], extensions: SERVE_EXTENSIONS)
    return head(:not_found) if abs.nil?

    return unless stale?(last_modified: File.mtime(abs))

    ext = File.extname(abs).downcase
    mime = MIME_TYPES[ext] || "application/octet-stream"

    # Rack::Files (unlike send_file) answers Range requests with 206, which
    # video/audio seeking, resume and Safari playback all require.
    status, headers, body = Rack::Files.new(File.dirname(abs)).serving(request, abs)
    headers["content-type"] = mime
    headers["cache-control"] = "private, max-age=0, must-revalidate"
    headers.each { |name, value| response.set_header(name, value) }
    self.status = status
    self.response_body = body
  end

  def extract
    folder_index = params[:src].to_i
    abs = resolve_kb_path(folder_index, params[:file], extensions: EXTRACTABLE_EXTENSIONS)
    return head(:not_found) if abs.nil?

    KnowledgeExtraction.enqueue_for_kb(folder_index: folder_index, kb_path: abs)
    redirect_to kb_path(src: folder_index, file: params[:file]),
                notice: "Knowledge extraction queued for #{File.basename(abs)}."
  end

  # ── Tree file operations ──────────────────────────────────────────────

  def edit
    folder_index = params[:src].to_i
    abs = resolve_kb_path(folder_index, params[:file], extensions: MARKDOWN_EXTENSIONS)
    return head(:not_found) if abs.nil?

    @selected_file = params[:file]
    @selected_folder_index = folder_index
    @raw_content = File.read(abs)
    remember_document(folder_index, @selected_file)
  end

  def fs_save
    folder_index = params[:src].to_i
    abs = resolve_kb_path(folder_index, params[:file], extensions: MARKDOWN_EXTENSIONS)
    return head(:not_found) if abs.nil?

    File.write(abs, params[:content].to_s)
    redirect_to kb_file_path(src: folder_index, file: params[:file])
  end

  def fs_create
    base = writable_base(params[:src].to_i)
    return fs_error("Folder is not available.") if base.nil?

    parent = resolve_dir(base, params[:dir])
    return fs_error("Target folder not found.") if parent.nil?

    name = params[:name].to_s.strip

    # A URL instead of a name means "download this into the folder in the
    # background" (yt-dlp for media, HTTP otherwise). URLs contain "/" so this
    # must run before valid_node_name?, which rejects them.
    if params[:kind] != "folder" && url?(name)
      KbDownload.enqueue(user: @user, source_index: params[:src].to_i,
                         dir: params[:dir].to_s, url: name, format: params[:format].to_s)
      return respond_fs(notice: "Downloading… it will appear in the tree when ready.")
    end

    return fs_error("Invalid name.") unless valid_node_name?(name)

    if params[:kind] == "folder"
      abs = File.join(parent, name)
      return fs_error("\"#{name}\" already exists.") if File.exist?(abs)
      Dir.mkdir(abs)
      respond_fs(notice: "Folder \"#{name}\" created.")
    else
      name = "#{name}.md" unless ALL_EXTENSIONS.include?(File.extname(name).downcase)
      abs = File.join(parent, name)
      return fs_error("\"#{name}\" already exists.") if File.exist?(abs)
      File.write(abs, "")
      respond_fs(file: abs.delete_prefix("#{base}/"), notice: "File \"#{name}\" created.")
    end
  end

  def fs_rename
    base = writable_base(params[:src].to_i)
    return fs_error("Folder is not available.") if base.nil?

    abs = safe_abs(base, params[:path])
    return fs_error("Not found.") if abs.nil? || abs == base || !File.exist?(abs)

    name = params[:name].to_s.strip
    return fs_error("Invalid name.") unless valid_node_name?(name)

    if File.file?(abs)
      name = "#{name}#{File.extname(abs)}" if File.extname(name).empty?
      return fs_error("Unsupported file extension.") unless ALL_EXTENSIONS.include?(File.extname(name).downcase)
    end

    dest = File.join(File.dirname(abs), name)
    return fs_error("\"#{name}\" already exists.") if File.exist?(dest) && dest != abs

    File.rename(abs, dest)
    if File.file?(dest)
      respond_fs(file: dest.delete_prefix("#{base}/"), notice: "Renamed to \"#{name}\".")
    else
      respond_fs(notice: "Renamed to \"#{name}\".")
    end
  end

  def fs_move
    base = writable_base(params[:src].to_i)
    dest_index = (params[:dest_src].presence || params[:src]).to_i
    dest_base = writable_base(dest_index)
    return fs_error("Folder is not available.") if base.nil? || dest_base.nil?

    abs = safe_abs(base, params[:path])
    return fs_error("Not found.") if abs.nil? || abs == base || !File.exist?(abs)

    dest_dir = resolve_dir(dest_base, params[:dest_dir])
    return fs_error("Target folder not found.") if dest_dir.nil?

    if File.directory?(abs) && (dest_dir == abs || dest_dir.start_with?("#{abs}/"))
      return fs_error("Cannot move a folder into itself.")
    end
    return respond_fs if File.dirname(abs) == dest_dir

    target = File.join(dest_dir, File.basename(abs))
    return fs_error("\"#{File.basename(abs)}\" already exists in the target folder.") if File.exist?(target)

    FileUtils.mv(abs, target)
    if File.file?(target)
      respond_fs(src: dest_index, file: target.delete_prefix("#{dest_base}/"), notice: "Moved \"#{File.basename(abs)}\".")
    else
      respond_fs(src: dest_index, notice: "Moved \"#{File.basename(abs)}\".")
    end
  end

  def fs_delete
    base = writable_base(params[:src].to_i)
    return fs_error("Folder is not available.") if base.nil?

    abs = safe_abs(base, params[:path])
    return fs_error("Not found.") if abs.nil? || abs == base || !File.exist?(abs)

    File.directory?(abs) ? FileUtils.rm_r(abs) : File.delete(abs)
    respond_fs(notice: "Deleted \"#{File.basename(abs)}\".")
  end

  private

  def fs_error(message)
    respond_fs(alert: message)
  end

  # Renders the tree (and, when the selection changed, the content pane) as a
  # turbo stream so file ops update in place instead of reloading the page.
  # Falls back to a full redirect for non-turbo clients.
  def respond_fs(file: nil, src: params[:src].to_i, notice: nil, alert: nil)
    unless request.format.turbo_stream?
      return redirect_to kb_path(src: src, file: file), notice: notice, alert: alert
    end

    flash.now[:notice] = notice if notice
    flash.now[:alert]  = alert if alert
    @folders = build_folder_tree
    if file
      @selected_file = file
      @selected_folder_index = src
      @content = render_file(src, file)
      remember_document(src, file) if displayable_content?(@content)
      @update_content = true
    else
      # Keep the doc the user had open highlighted; clear the pane if it's
      # gone (deleted, or inside a renamed/moved folder).
      sel_src  = params[:sel_src].to_i
      sel_file = params[:sel_file].presence
      if sel_file && resolve_kb_path(sel_src, sel_file, extensions: ALL_EXTENSIONS)
        @selected_file = sel_file
        @selected_folder_index = sel_src
      elsif sel_file
        @update_content = true
      end
    end
    render "kb/fs_stream"
  end

  # Base directory of a KB source, only if it can be written to.
  # The native source is created on demand; user folders must already exist.
  def writable_base(folder_index)
    sources = kb_sources
    return nil if folder_index.negative? || folder_index >= sources.size

    source = sources[folder_index]
    base = File.expand_path(source[:path])
    FileUtils.mkdir_p(base) if source[:native] && !Dir.exist?(base)
    Dir.exist?(base) ? base : nil
  end

  # Expands rel inside base, nil when it escapes the source root.
  def safe_abs(base, rel)
    return nil if rel.blank?

    abs = File.expand_path(File.join(base, rel))
    abs.start_with?("#{base}/") || abs == base ? abs : nil
  end

  # Resolves a relative directory ("" means the source root).
  def resolve_dir(base, rel)
    return base if rel.blank?

    abs = safe_abs(base, rel)
    abs && File.directory?(abs) ? abs : nil
  end

  def url?(str)
    str.match?(%r{\Ahttps?://\S+\z}i)
  end

  def valid_node_name?(name)
    name.present? &&
      name.length <= 255 &&
      !name.start_with?(".") &&
      name.match?(%r{\A[^/\\\0]+\z})
  end

  def build_folder_tree
    kb_sources.each_with_index.map do |source, idx|
      path = source[:path]
      expanded = File.expand_path(path)
      files = []
      dirs = []
      if Dir.exist?(expanded)
        entries = Dir.glob(File.join(expanded, "**", "*"))
        files = entries
                   .select { |f| File.file?(f) && ALL_EXTENSIONS.include?(File.extname(f).downcase) }
                   .sort
                   .map { |f| { rel: f.sub("#{expanded}/", ""), abs: f } }
        dirs = entries
                  .select { |d| File.directory?(d) }
                  .sort
                  .map { |d| d.sub("#{expanded}/", "") }
      end
      tree = build_nested_tree(files, dirs)
      {
        index: idx,
        path: path,
        label: source[:label] || folder_label(path),
        files: files,
        tree: tree,
        exists: Dir.exist?(expanded),
        native: source[:native],
        drive: source[:drive]
      }
    end
  end

  def kb_sources
    KbSource.list(@user)
  end

  def folder_label(path)
    File.basename(path.to_s.chomp(File::SEPARATOR)).presence || path.to_s
  end

  def build_nested_tree(files, dirs = [])
    root = {}
    dirs.each do |rel|
      dir_node_for(root, rel.split("/"))
    end
    files.each do |file|
      parts = file[:rel].split("/")
      current = parts.size > 1 ? dir_node_for(root, parts[0..-2]) : root
      current[parts.last] = { type: :file, rel: file[:rel], abs: file[:abs] }
    end
    root
  end

  def initial_document_selection
    return [params[:src].to_i, params[:file]] if params[:file].present?

    remembered = remembered_document
    if remembered && resolve_kb_path(remembered.first, remembered.last, extensions: ALL_EXTENSIONS)
      return remembered
    end

    folder = @folders.find { |candidate| candidate[:files].any? }
    return [0, nil] unless folder

    [folder[:index], folder[:files].first[:rel]]
  end

  def remembered_document
    value = cookies.encrypted[LAST_DOCUMENT_COOKIE]
    return if value.blank?

    parsed = JSON.parse(value)
    [Integer(parsed.fetch("src")), parsed.fetch("file").to_s]
  rescue JSON::ParserError, KeyError, TypeError, ArgumentError
    nil
  end

  def remember_document(folder_index, rel_path)
    cookies.permanent.encrypted[LAST_DOCUMENT_COOKIE] = {
      value: { src: folder_index, file: rel_path }.to_json,
      httponly: true,
      same_site: :lax
    }
  end

  def displayable_content?(content)
    content.present? && content.kind != :missing
  end

  # Walks/creates dir nodes for the given path parts, returns the children
  # hash of the deepest one. Dir nodes carry their own rel path for tree ops.
  def dir_node_for(root, parts)
    current = root
    parts.each_with_index do |dir, i|
      current[dir] ||= { type: :dir, children: {}, rel: parts[0..i].join("/") }
      current = current[dir][:children]
    end
    current
  end

  def render_file(folder_index, rel_path)
    return nil if rel_path.blank?

    abs = resolve_kb_path(folder_index, rel_path, extensions: ALL_EXTENSIONS)
    return KbContent.new(kind: :missing) if abs.nil?

    ext = File.extname(abs).downcase
    metadata = file_metadata(abs, folder_index, rel_path)

    if MARKDOWN_EXTENSIONS.include?(ext)
      KbContent.new(**metadata, kind: :markdown, html: render_markdown(File.read(abs)))
    elsif EMBED_EXTENSIONS.include?(ext)
      KbContent.new(**metadata, kind: :embed, raw_url: kb_raw_path(src: folder_index, file: rel_path))
    elsif PDF_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :pdf,
        serve_url: kb_serve_path(src: folder_index, file: rel_path),
        extraction: KnowledgeExtraction.where(kb_path: abs).recent.first,
        output_rel: output_rel_for(abs, rel_path)
      )
    elsif IMAGE_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :image,
        serve_url: kb_serve_path(src: folder_index, file: rel_path),
        mime_type: MIME_TYPES[ext],
        extraction: KnowledgeExtraction.where(kb_path: abs).recent.first,
        output_rel: output_rel_for(abs, rel_path)
      )
    elsif VIDEO_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :video,
        serve_url: kb_serve_path(src: folder_index, file: rel_path),
        mime_type: MIME_TYPES[ext]
      )
    elsif AUDIO_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :audio,
        serve_url: kb_serve_path(src: folder_index, file: rel_path),
        mime_type: MIME_TYPES[ext]
      )
    elsif LONG_DOC_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :long_doc,
        extraction: KnowledgeExtraction.where(kb_path: abs).recent.first,
        output_rel: output_rel_for(abs, rel_path)
      )
    else
      KbContent.new(kind: :missing)
    end
  end

  def file_metadata(abs, folder_index, rel_path)
    stat = File.stat(abs)
    {
      rel: rel_path,
      src: folder_index,
      filename: File.basename(abs),
      created_at: file_created_at(stat),
      modified_at: stat.mtime
    }
  end

  def file_created_at(stat)
    stat.birthtime
  rescue NotImplementedError, Errno::EINVAL
    stat.ctime
  end

  def output_rel_for(abs, rel_path)
    dir = File.dirname(abs)
    base = File.basename(abs, File.extname(abs))
    %W[#{base}.md #{base}.extracted.md].each do |name|
      candidate = File.join(dir, name)
      next unless File.exist?(candidate)

      rel_dir = File.dirname(rel_path)
      return rel_dir == "." ? name : File.join(rel_dir, name)
    end
    nil
  end

  def resolve_kb_path(folder_index, rel_path, extensions: KB_EXTENSIONS)
    return nil if rel_path.blank?

    sources = kb_sources
    return nil if folder_index.negative? || folder_index >= sources.size

    base = File.expand_path(sources[folder_index][:path])
    abs = File.expand_path(File.join(base, rel_path))

    return nil unless abs.start_with?(base + "/") || abs == base
    return nil unless File.exist?(abs) && File.file?(abs)
    return nil unless extensions.include?(File.extname(abs).downcase)

    abs
  end

  def render_markdown(raw)
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener" }
    )
    md = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      no_intra_emphasis: true
    )
    md.render(raw).html_safe
  end
end
