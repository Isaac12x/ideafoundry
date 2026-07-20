class KbController < ApplicationController
  NATIVE_KB_PATH = KbSource::NATIVE_PATH
  NATIVE_KB_LABEL = KbSource::NATIVE_LABEL
  LAST_DOCUMENT_COOKIE = :kb_last_document

  MARKDOWN_EXTENSIONS   = Kb::MediaTypes::MARKDOWN_EXTENSIONS
  EMBED_EXTENSIONS      = Kb::MediaTypes::EMBED_EXTENSIONS
  PDF_EXTENSIONS        = Kb::MediaTypes::PDF_EXTENSIONS
  IMAGE_EXTENSIONS      = Kb::MediaTypes::IMAGE_EXTENSIONS
  VIDEO_EXTENSIONS      = Kb::MediaTypes::VIDEO_EXTENSIONS
  AUDIO_EXTENSIONS      = Kb::MediaTypes::AUDIO_EXTENSIONS
  # TIF/TIFF: not renderable in browsers, extraction only
  LONG_DOC_EXTENSIONS   = Kb::MediaTypes::LONG_DOC_EXTENSIONS

  SERVE_EXTENSIONS      = (PDF_EXTENSIONS + IMAGE_EXTENSIONS + VIDEO_EXTENSIONS + AUDIO_EXTENSIONS).freeze
  EXTRACTABLE_EXTENSIONS = (PDF_EXTENSIONS + IMAGE_EXTENSIONS + LONG_DOC_EXTENSIONS).freeze
  KB_EXTENSIONS         = (MARKDOWN_EXTENSIONS + EMBED_EXTENSIONS).freeze
  ALL_EXTENSIONS        = (KB_EXTENSIONS + SERVE_EXTENSIONS + LONG_DOC_EXTENSIONS).freeze

  EMBED_CSP = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:".freeze

  MIME_TYPES = Kb::MediaTypes::MIME_TYPES

  KbContent = Struct.new(
    :kind, :html, :raw_url, :serve_url, :rel, :src, :filename,
    :created_at, :modified_at,
    :extraction, :output_rel, :mime_type,
    keyword_init: true
  )

  before_action :set_user
  # Only the KB section page is feature-gated; file/tree/serve endpoints also
  # back the notes bar and stay available.
  before_action -> { require_feature(:kb) }, only: [:index]

  def index
    @folders = build_folder_tree
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
    abs = resolve_kb_path(params[:src].to_i, params[:file], extensions: :any)
    return head(:not_found) if abs.nil?

    ext = File.extname(abs).downcase
    unless SERVE_EXTENSIONS.include?(ext)
      return send_file(abs, filename: File.basename(abs), disposition: "attachment", type: "application/octet-stream")
    end

    return unless stale?(last_modified: File.mtime(abs))

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
    abs = resolve_kb_path(folder_index, params[:file], extensions: :any)
    return head(:not_found) if abs.nil?

    @selected_file = params[:file]
    @selected_folder_index = folder_index
    remember_document(folder_index, @selected_file)

    if MARKDOWN_EXTENSIONS.include?(File.extname(abs).downcase)
      @raw_content = File.read(abs)
      return render :edit
    end

    @content = render_file(folder_index, @selected_file)
    @media_info = Kb::MediaInspector.new(abs).call
    if %w[.html .htm].include?(File.extname(abs).downcase)
      @source_content = File.read(abs)
    end
    render :media_edit
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

  def fs_upload
    source_index = params[:src].to_i
    base = writable_base(source_index)
    return fs_error("Folder is not available.") if base.nil?

    parent = resolve_dir(base, params[:dir])
    return fs_error("Target folder not found.") if parent.nil?

    uploads = Array(params[:files]).select { |upload| upload.respond_to?(:tempfile) }
    return fs_error("Choose at least one file to copy.") if uploads.empty?

    copied = uploads.map do |upload|
      name = sanitized_upload_name(upload.original_filename)
      next if name.blank?

      destination = unique_fs_path(File.join(parent, name))
      upload.tempfile.rewind
      File.open(destination, "wb") { |file| IO.copy_stream(upload.tempfile, file) }
      destination
    end.compact
    return fs_error("The dropped files did not have usable names.") if copied.empty?

    respond_fs(notice: "Copied #{copied.size} #{'file'.pluralize(copied.size)} into the knowledge base.")
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
    KbEntryPreference.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: base,
      new_relative_path: dest.delete_prefix("#{base}/")
    )
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
    KbEntryPreference.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: dest_base,
      new_relative_path: target.delete_prefix("#{dest_base}/")
    )
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
    KbEntryPreference.delete_subtree!(user: @user, source_path: base, relative_path: params[:path])
    respond_fs(notice: "Deleted \"#{File.basename(abs)}\".")
  end

  def fs_preference
    source_index = params[:src].to_i
    source = kb_sources[source_index]
    return fs_error("Knowledge-base source is not available.") unless source

    base = File.expand_path(source[:path])
    entry_type = params[:entry_type].to_s
    relative_path = KbEntryPreference.normalize_relative_path(params[:path])
    return fs_error("Unsupported knowledge-base entry.") unless %w[root folder file].include?(entry_type)
    return fs_error("Knowledge-base entry was not found.") unless valid_preference_target?(base, relative_path, entry_type)

    preference = KbEntryPreference.find_or_initialize_entry(
      user: @user,
      source_path: base,
      relative_path: relative_path,
      entry_type: entry_type
    )
    preference.favorite = ActiveModel::Type::Boolean.new.cast(params[:favorite]) if params.key?(:favorite)
    preference.save!

    if params[:icon_kind].present?
      return fs_error("Only folder icons can be changed.") unless %w[root folder].include?(entry_type)

      preference.set_icon!(kind: params[:icon_kind], emoji: params[:emoji], image: params[:icon_image])
    end
    preference.destroy! if !preference.favorite? && preference.icon_kind == "default" && !preference.icon_image.attached?

    respond_fs(notice: params.key?(:favorite) ? "Favourite updated." : "Folder icon updated.")
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    fs_error(error.message)
  end

  def fs_open
    source_index = params[:src].to_i
    source = kb_sources[source_index]
    return render(json: { error: "Knowledge-base source is not available." }, status: :not_found) unless source

    base = File.expand_path(source[:path])
    relative_path = params[:path].to_s
    absolute = relative_path.blank? ? base : safe_abs(base, relative_path)
    return render(json: { error: "Knowledge-base entry was not found." }, status: :not_found) unless absolute && File.exist?(absolute)

    command = File.file?(absolute) ? ["open", "-R", absolute] : ["open", absolute]
    if system(*command)
      head :no_content
    else
      render json: { error: "Finder could not open this entry." }, status: :unprocessable_content
    end
  end

  def tree
    folders = build_folder_tree
    render turbo_stream: turbo_stream.replace(
      "kb-sidebar-tree",
      partial: "kb/tree",
      locals: {
        folders: folders,
        selected_file: params[:sel_file].presence,
        selected_folder_index: params[:sel_src].presence&.to_i
      }
    )
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
      if sel_file && resolve_kb_path(sel_src, sel_file, extensions: :any)
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
    return nil unless abs.start_with?("#{base}/") || abs == base
    return nil if symlink_in_path?(base, abs)

    abs
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
    Kb::TreeBuilder.new(@user).call
  end

  def kb_sources
    KbSource.list(@user)
  end

  def initial_document_selection
    return [params[:src].to_i, params[:file]] if params[:file].present?

    remembered = remembered_document
    if remembered && resolve_kb_path(remembered.first, remembered.last, extensions: :any)
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

  def render_file(folder_index, rel_path)
    return nil if rel_path.blank?

    abs = resolve_kb_path(folder_index, rel_path, extensions: :any)
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
      KbContent.new(
        **metadata,
        kind: :generic,
        serve_url: kb_serve_path(src: folder_index, file: rel_path),
        mime_type: "application/octet-stream"
      )
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
    return nil if symlink_in_path?(base, abs)
    return nil unless File.exist?(abs) && File.file?(abs)
    return nil unless extensions == :any || extensions.include?(File.extname(abs).downcase)

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

  def sanitized_upload_name(filename)
    File.basename(filename.to_s).gsub(/[\\\/\0]/, "_").sub(/\A\.+/, "").strip.first(255)
  end

  def unique_fs_path(path)
    return path unless File.exist?(path)

    directory = File.dirname(path)
    extension = File.extname(path)
    stem = File.basename(path, extension)
    number = 2
    number += 1 while File.exist?(File.join(directory, "#{stem}-#{number}#{extension}"))
    File.join(directory, "#{stem}-#{number}#{extension}")
  end

  def valid_preference_target?(base, relative_path, entry_type)
    return Dir.exist?(base) if entry_type == "root" && relative_path.blank?

    absolute = safe_abs(base, relative_path)
    return false unless absolute

    entry_type == "folder" ? File.directory?(absolute) : File.file?(absolute)
  end

  def symlink_in_path?(base, absolute)
    relative = absolute.delete_prefix(base).delete_prefix("/")
    current = base
    relative.split("/").any? do |segment|
      current = File.join(current, segment)
      File.symlink?(current)
    end
  end
end
