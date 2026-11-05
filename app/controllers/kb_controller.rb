class KbController < ApplicationController
  include KbProjects

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
  EXTRACTABLE_EXTENSIONS = (PDF_EXTENSIONS + Kb::MediaTypes::OCR_EXTENSIONS + LONG_DOC_EXTENSIONS).freeze
  KB_EXTENSIONS         = (MARKDOWN_EXTENSIONS + EMBED_EXTENSIONS).freeze
  ALL_EXTENSIONS        = (KB_EXTENSIONS + SERVE_EXTENSIONS + LONG_DOC_EXTENSIONS + Kb::MediaTypes::VIEWER_EXTENSIONS).freeze

  EMBED_CSP = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:".freeze

  # Placeholders for nodes created straight from the tree, before naming.
  UNNAMED_FILE = "Untitled.md".freeze
  UNNAMED_FOLDER = "Untitled folder".freeze

  MIME_TYPES = Kb::MediaTypes::MIME_TYPES

  KbContent = Struct.new(
    :kind, :html, :raw_url, :serve_url, :rel, :src, :filename,
    :created_at, :modified_at,
    :extraction, :output_rel, :mime_type, :captions_url, :private_project, :shots,
    keyword_init: true
  )

  before_action :set_user
  # Only the KB section page is feature-gated; file/tree/serve endpoints also
  # back the notes bar and stay available.
  before_action -> { require_feature(:kb) }, only: [ :index ]
  before_action :block_locking_writes, only: %i[fs_save fs_create fs_upload fs_rename fs_move fs_delete]

  def index
    @folders = build_folder_tree
    @selected_folder_index, @selected_file = initial_document_selection
    # A file inside a locked project (remembered, linked or the first one): show the locked page instead.
    if (locked = locked_project_at(@selected_folder_index, @selected_file))
      return redirect_to kb_path(src: @selected_folder_index, project: locked.rel)
    end

    @content = render_file(@selected_folder_index, @selected_file)
    remember_document(@selected_folder_index, @selected_file) if displayable_content?(@content)
    @facts = @user.facts.recent
    @maxims = @user.maxims.recent
  end

  def file
    folder_index = params[:src].to_i
    rel_path = params[:file]
    if (locked = locked_project_at(folder_index, rel_path))
      return redirect_to kb_project_path(src: folder_index, path: locked.rel)
    end

    @content = render_file(folder_index, rel_path)
    @selected_file = rel_path
    @selected_folder_index = folder_index
    remember_document(folder_index, rel_path) if displayable_content?(@content)
    mark_download_opened(folder_index, rel_path) if @content&.kind != :missing
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
    unless SERVE_EXTENSIONS.include?(ext) || ext == ".vtt" # .vtt: sidecar captions for <track>
      return send_file(abs, filename: File.basename(abs), disposition: "attachment", type: "application/octet-stream")
    end

    return unless stale?(last_modified: File.mtime(abs), etag: [ (File.mtime(abs).to_f * 1000).to_i, File.size(abs) ])

    mime = ext == ".vtt" ? "text/vtt" : MIME_TYPES[ext] || "application/octet-stream"

    # Rack::Files (unlike send_file) answers Range requests with 206, which
    # video/audio seeking, resume and Safari playback all require.
    status, headers, body = Rack::Files.new(File.dirname(abs)).serving(request, abs)
    headers["content-type"] = mime
    # SVG can carry script: it is only ever shown via <img>, and opened directly it is sandboxed and inert.
    headers["content-security-policy"] = "sandbox; default-src 'none'; style-src 'unsafe-inline'" if ext == ".svg"
    headers["x-content-type-options"] = "nosniff" if ext == ".svg"
    headers["cache-control"] = "private, max-age=0, must-revalidate"
    headers.each { |name, value| response.set_header(name, value) }
    self.status = status
    self.response_body = body
  end

  def extract
    folder_index = params[:src].to_i
    abs = resolve_kb_path(folder_index, params[:file], extensions: EXTRACTABLE_EXTENSIONS)
    return head(:not_found) if abs.nil?
    # Extraction sends file bytes to the OCR service; never for private projects.
    return head(:forbidden) if Kb::Privacy.private?(File.expand_path(kb_sources[folder_index][:path]), params[:file])

    KnowledgeExtraction.enqueue_for_kb(folder_index: folder_index, kb_path: abs)
    redirect_to kb_path(src: folder_index, file: params[:file])
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
    Kb::TreeBuilder.bust_cache!(@user)
    redirect_to kb_file_path(src: folder_index, file: params[:file])
  end

  def fs_create
    base = writable_base(params[:src].to_i)
    return fs_error("Folder is not available.") if base.nil?

    parent = resolve_dir(base, params[:dir])
    return fs_error("Target folder not found.") if parent.nil?

    name = params[:name].to_s.strip
    return project_create(parent, name) if params[:kind] == "project"
    # Pasted wrapper links (suspended tab, redirectors) reduce to the real URL.
    unwrapped = Kb::UrlNormalizer.call(name)
    name = unwrapped if url?(unwrapped)

    folder = params[:kind] == "folder"

    # A URL instead of a name means "download this into the folder in the
    # background" (yt-dlp for media, HTTP otherwise). URLs contain "/" so this
    # must run before valid_node_name?, which rejects them.
    if !folder && url?(name)
      if CaptureJob.extension_url?(name)
        job = @user.capture_jobs.create(url: name, file_format: "md",
                                        source_index: params[:src].to_i, dir: params[:dir].to_s)
        return fs_error(job.errors.full_messages.to_sentence) unless job.persisted?

        return respond_fs(notice: "Sent to the browser extension. It will save the conversation here within about 30 seconds.")
      end
      return fs_error("Project is locked. Unlock it first.") if Kb::ProjectLock.write_block(base, params[:dir]) == :locked

      KbDownload.enqueue(user: @user, source_index: params[:src].to_i,
                         dir: params[:dir].to_s, url: name, format: params[:format].to_s,
                         clip_start: params[:clip_start], clip_end: params[:clip_end], note: params[:note])
      return respond_fs
    end

    # No name: create the node under a placeholder and hand it straight back
    # for inline naming in the tree, so nobody types into a dialog first.
    if name.blank?
      abs = unique_fs_path(File.join(parent, folder ? UNNAMED_FOLDER : UNNAMED_FILE))
      folder ? Dir.mkdir(abs) : File.write(abs, "")
      move_into_folder(base, abs, Array(params[:move])) if folder
      return respond_fs(editing: abs.delete_prefix("#{base}/"))
    end

    return fs_error("Invalid name.") unless valid_node_name?(name)

    if folder
      abs = File.join(parent, name)
      return fs_error("\"#{name}\" already exists.") if File.exist?(abs)
      Dir.mkdir(abs)
      respond_fs
    else
      name = "#{name}.md" unless ALL_EXTENSIONS.include?(File.extname(name).downcase)
      abs = File.join(parent, name)
      return fs_error("\"#{name}\" already exists.") if File.exist?(abs)
      File.write(abs, "")
      respond_fs(file: abs.delete_prefix("#{base}/"))
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

    respond_fs
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

    side = Kb::Transcript.sidecar_for(abs)
    note = Kb::Note.sidecar_for(abs)
    File.rename(abs, dest)
    FileUtils.mv(side, Kb::Transcript.sidecar(dest)) if side && !File.exist?(Kb::Transcript.sidecar(dest)) # captions follow their media
    Kb::Note.carry!(note, dest)
    Kb::VideoShots.carry!(abs, dest) if Kb::MediaTypes.kind_for(dest) == :video
    rel = dest.delete_prefix("#{base}/")
    parent_rel = File.dirname(params[:path].to_s)
    Kb::Project.at(base, parent_rel)&.rename_material!(File.basename(params[:path].to_s), name) unless parent_rel == "."
    reorder_child(base, params[:path], to: name)
    KbEntryPreference.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: base,
      new_relative_path: rel
    )
    IdeaKbLink.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: base,
      new_relative_path: rel
    )
    KbLink.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: base,
      new_relative_path: rel
    )
    KbAnnotation.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: base,
      new_relative_path: rel
    )
    KbBookmark.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: base,
      new_relative_path: rel
    )
    KbDownload.move_subtree!(user: @user, source_index: params[:src].to_i, old_relative_path: params[:path],
                             new_source_index: params[:src].to_i, new_relative_path: rel)

    # Inline naming patches the one row it changed, so it wants the new path
    # back rather than a fresh tree. The cached scan must still be dropped, or
    # the next tree poll/refresh serves the old name.
    Kb::TreeBuilder.bust_cache!(@user)
    return render(json: { rel: rel, name: name }) if request.format.json?

    if File.file?(dest)
      respond_fs(file: rel)
    else
      respond_fs
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

    side = Kb::Transcript.sidecar_for(abs)
    note = Kb::Note.sidecar_for(abs)
    FileUtils.mv(abs, target)
    FileUtils.mv(side, Kb::Transcript.sidecar(target)) if side && !File.exist?(Kb::Transcript.sidecar(target))
    Kb::Note.carry!(note, target)
    Kb::VideoShots.carry!(abs, target) if Kb::MediaTypes.kind_for(target) == :video
    reorder_child(base, params[:path])
    KbEntryPreference.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: dest_base,
      new_relative_path: target.delete_prefix("#{dest_base}/")
    )
    IdeaKbLink.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: dest_base,
      new_relative_path: target.delete_prefix("#{dest_base}/")
    )
    KbLink.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: dest_base,
      new_relative_path: target.delete_prefix("#{dest_base}/")
    )
    KbAnnotation.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: dest_base,
      new_relative_path: target.delete_prefix("#{dest_base}/")
    )
    KbBookmark.move_subtree!(
      user: @user,
      source_path: base,
      old_relative_path: params[:path],
      new_source_path: dest_base,
      new_relative_path: target.delete_prefix("#{dest_base}/")
    )
    KbDownload.move_subtree!(user: @user, source_index: params[:src].to_i, old_relative_path: params[:path],
                             new_source_index: dest_index, new_relative_path: target.delete_prefix("#{dest_base}/"))
    apply_drop_order(dest_base, dest_dir, File.basename(target))
    if File.file?(target)
      respond_fs(src: dest_index, file: target.delete_prefix("#{dest_base}/"))
    else
      respond_fs(src: dest_index)
    end
  end

  def fs_delete
    base = writable_base(params[:src].to_i)
    return fs_error("Folder is not available.") if base.nil?

    abs = safe_abs(base, params[:path])
    return fs_error("Not found.") if abs.nil? || abs == base || !File.exist?(abs)

    side = Kb::Transcript.sidecar_for(abs)
    note = Kb::Note.sidecar_for(abs)
    File.directory?(abs) ? FileUtils.rm_r(abs) : File.delete(abs)
    FileUtils.rm_f([ side, note ].compact)
    reorder_child(base, params[:path])
    KbEntryPreference.delete_subtree!(user: @user, source_path: base, relative_path: params[:path])
    IdeaKbLink.delete_subtree!(user: @user, source_path: base, relative_path: params[:path])
    KbLink.delete_subtree!(user: @user, source_path: base, relative_path: params[:path])
    KbAnnotation.delete_subtree!(user: @user, source_path: base, relative_path: params[:path])
    KbBookmark.delete_subtree!(user: @user, source_path: base, relative_path: params[:path])
    respond_fs
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
    preference.destroy! if preference.blank_preference?

    # Favouriting is toggled optimistically in the tree; acknowledging is
    # enough, and a banner for a starred file is noise.
    return head(:no_content) if request.format.json?

    respond_fs
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

    command = File.file?(absolute) ? [ "open", "-R", absolute ] : [ "open", absolute ]
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

  # Global default (user.settings), or one folder's override when src is given
  # (blank mode clears it). Overrides live on the folder's KbEntryPreference.
  def sort
    mode = params[:mode].to_s
    folder_scope = params.key?(:src)
    return fs_error("Unsupported sort order.") unless Kb::TreeBuilder::SORT_MODES.include?(mode) || (folder_scope && mode.blank?)

    if folder_scope
      error = save_folder_pref(params[:src].to_i, params[:path]) { |pref| pref.sort_mode = mode.presence }
      return fs_error(error) if error
    else
      @user.settings = (@user.settings || {}).deep_merge("kb" => { "sort" => mode })
      @user.save!
    end
    return head(:no_content) if request.format.json?
    return redirect_to(kb_path) unless request.format.turbo_stream?

    # Not respond_fs: that would drop the open file's highlight.
    Kb::TreeBuilder.bust_cache!(@user)
    @folders = build_folder_tree
    @selected_folder_index, @selected_file = remembered_document
    render turbo_stream: [
      turbo_stream.replace("kb-sidebar-tree", partial: "kb/tree"),
      turbo_stream.replace("kb-sort", partial: "kb/sort", locals: { mode: Kb::TreeBuilder.sort_mode_for(@user) })
    ]
  end

  # Persists a drag/keyboard reorder: params[:names] is the full sibling order
  # as displayed. Switches the folder to manual (ascending) so it sticks; files untouched.
  def order
    names = Array(params[:names]).map(&:to_s).uniq
    error = save_folder_pref(params[:src].to_i, params[:dir]) do |pref, dir_abs|
      pref.sort_mode = "manual_asc"
      pref.manual_order = existing_children(dir_abs, params[:dir], names).to_json
    end
    return fs_error(error) if error

    respond_fs
  end

  private

  # Names that are real entries of the folder or alias slots shown in it.
  def existing_children(dir_abs, dir_rel, names)
    base = File.expand_path(dir_abs.to_s)
    source = kb_sources.map { |src| File.expand_path(src[:path]) }.find { |path| base == path || base.start_with?("#{path}/") }
    slots = source ? KbLink.aliases_in(@user, source).pluck(:peer_relative_path).to_set : Set.new
    rel = KbEntryPreference.normalize_relative_path(dir_rel)
    names.select { |n| valid_node_name?(n) && (File.exist?(File.join(dir_abs, n)) || slots.include?(rel.empty? ? n : "#{rel}/#{n}")) }
  end

  # Yields (folder preference, absolute dir) for a source folder, saves it, drops it if blank
  # and busts the tree cache. Returns an error string or nil.
  def save_folder_pref(source_index, dir_rel)
    base = writable_base(source_index)
    return "Folder is not available." if base.nil?

    dir_abs = resolve_dir(base, dir_rel.to_s)
    return "Target folder not found." if dir_abs.nil?

    pref = KbEntryPreference.folder_pref(@user, base, dir_rel)
    yield pref, dir_abs
    pref.save!
    pref.destroy! if pref.blank_preference?
    Kb::TreeBuilder.bust_cache!(@user)
    nil
  rescue ActiveRecord::RecordInvalid => error
    error.message
  end

  # A drop between siblings of another folder sends that folder's order (params[:names]);
  # otherwise the moved entry lands last in a manual folder.
  def apply_drop_order(dest_base, dest_dir, name)
    rel = dest_dir.delete_prefix(dest_base).delete_prefix("/")
    given = Array(params[:names]).map(&:to_s)
    if given.include?(name)
      save_folder_pref(params[:dest_src].presence&.to_i || params[:src].to_i, rel) do |pref, dir_abs|
        pref.sort_mode = "manual_asc"
        pref.manual_order = existing_children(dir_abs, rel, given).to_json
      end
    else
      KbEntryPreference.edit_order!(@user, dest_base, rel) { |names| names + [ name ] }
    end
  end

  # Keeps a folder's manual order in step with a child being renamed (to: new name),
  # moved out or deleted (to: nil).
  def reorder_child(base, path, to: nil)
    dir = File.dirname(path.to_s)
    old = File.basename(path.to_s)
    KbEntryPreference.edit_order!(@user, base, dir == "." ? "" : dir) do |names|
      names.filter_map { |name| name == old ? to : name }
    end
  end

  # "New folder" with several files picked: move them (siblings only) into the fresh folder.
  def move_into_folder(base, folder, rels)
    rels.each do |rel|
      abs = safe_abs(base, rel)
      next if abs.nil? || !File.file?(abs) || File.dirname(abs) != File.dirname(folder)

      target = File.join(folder, File.basename(abs))
      next if File.exist?(target)

      note = Kb::Note.sidecar_for(abs)
      FileUtils.mv(abs, target)
      Kb::Note.carry!(note, target)
      Kb::VideoShots.carry!(abs, target) if Kb::MediaTypes.kind_for(target) == :video
      new_rel = target.delete_prefix("#{base}/")
      [ KbEntryPreference, IdeaKbLink, KbLink, KbAnnotation, KbBookmark ].each do |model|
        model.move_subtree!(user: @user, source_path: base, old_relative_path: rel,
                            new_source_path: base, new_relative_path: new_rel)
      end
    end
  end

  # A failed write (permissions, disk) must tell the user, not 500 into a Turbo no-op.
  rescue_from SystemCallError do |error|
    raise error unless action_name.start_with?("fs_")

    fs_error("Couldn't complete that: #{error.message.sub(/ @ .*? - /, " - ")}")
  end

  def fs_error(message)
    return render(json: { error: message }, status: :unprocessable_content) if request.format.json?

    respond_fs(alert: message)
  end

  # Renders the tree (and, when the selection changed, the content pane) as a
  # turbo stream so file ops update in place instead of reloading the page.
  # Falls back to a full redirect for non-turbo clients.
  def respond_fs(file: nil, src: params[:src].to_i, alert: nil, notice: nil, editing: nil)
    Kb::TreeBuilder.bust_cache!(@user) # before any early return: redirects re-render from the cache too
    unless request.format.turbo_stream?
      return redirect_to kb_path(src: src, file: file || editing), alert: alert, notice: notice
    end
    flash.now[:alert]  = alert if alert
    flash.now[:notice] = notice if notice
    @folders = build_folder_tree
    @editing_src = src if editing
    @editing_rel = editing
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

  # No writes into (or around) a project while it locks/unlocks: the archive
  # would miss them or the move would hit a half-empty folder.
  def block_locking_writes
    base = writable_base(params[:src].to_i) or return
    dest_base = writable_base((params[:dest_src].presence || params[:src]).to_i) || base
    paths = %i[path file dir].filter_map { |key| params[key].presence }.map { |rel| File.join(base, rel) }
    paths += Array(params[:move]).map { |rel| File.join(base, rel.to_s) }
    paths << File.join(dest_base, params[:dest_dir].to_s) if params[:dest_dir].present?
    return unless paths.any? { |path| Kb::ProjectLock.busy_path?(path) }

    fs_error("A project in that folder is locking or unlocking. Try again in a moment.")
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
    Kb::TreeBuilder.build(@user)
  end

  def kb_sources
    KbSource.list(@user)
  end

  def initial_document_selection
    return [ params[:src].to_i, params[:file] ] if params[:file].present?

    remembered = remembered_document
    if remembered && resolve_kb_path(remembered.first, remembered.last, extensions: :any)
      return remembered
    end

    # Locked projects only hold their .7z + stub: never auto-open those.
    folder = @folders.find { |candidate| candidate[:files].any? { |f| !locked_project_at(candidate[:index], f[:rel]) } }
    return [ 0, nil ] unless folder

    [ folder[:index], folder[:files].find { |f| !locked_project_at(folder[:index], f[:rel]) }[:rel] ]
  end

  def locked_project_at(folder_index, rel)
    source = (@lock_sources ||= kb_sources)[folder_index] unless folder_index.to_i.negative?
    return unless source && rel.present?

    project = Kb::Project.containing(File.expand_path(source[:path]), rel)
    project if project&.locked?
  end

  def remembered_document
    value = cookies.encrypted[LAST_DOCUMENT_COOKIE]
    return if value.blank?

    parsed = JSON.parse(value)
    [ Integer(parsed.fetch("src")), parsed.fetch("file").to_s ]
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
        serve_url: versioned_serve_path(abs, folder_index, rel_path),
        extraction: KnowledgeExtraction.where(kb_path: abs).recent.first,
        output_rel: output_rel_for(abs, rel_path)
      )
    elsif IMAGE_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :image,
        serve_url: versioned_serve_path(abs, folder_index, rel_path),
        mime_type: MIME_TYPES[ext],
        extraction: KnowledgeExtraction.where(kb_path: abs).recent.first,
        output_rel: output_rel_for(abs, rel_path)
      )
    elsif VIDEO_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :video,
        serve_url: versioned_serve_path(abs, folder_index, rel_path),
        mime_type: MIME_TYPES[ext],
        captions_url: (side = Kb::Transcript.sidecar_for(abs)) && versioned_serve_path(side, folder_index, Kb::Transcript.sidecar(rel_path)),
        shots: video_shots(abs, folder_index, rel_path)
      )
    elsif AUDIO_EXTENSIONS.include?(ext)
      KbContent.new(
        **metadata,
        kind: :audio,
        serve_url: versioned_serve_path(abs, folder_index, rel_path),
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
        kind: Kb::MediaTypes.kind_for(abs), # :generic, or a viewer kind (model, archive, book, comic, cad) fetched via serve
        serve_url: versioned_serve_path(abs, folder_index, rel_path),
        mime_type: "application/octet-stream"
      )
    end
  end

  # Captured frames in the video's sibling folder: [{ name:, time:, rel:, serve_url: }].
  def video_shots(abs, folder_index, rel_path)
    folder = Kb::VideoShots.dir(rel_path).delete_prefix("./")
    Kb::VideoShots.list(abs).map do |name, time|
      rel = File.join(folder, name)
      { name: name, time: time, rel: rel, serve_url: kb_serve_path(src: folder_index, file: rel) }
    end
  end

  # The mtime param busts browser image/media caches when an edit rewrites a
  # file in place (same URL otherwise reuses the old bytes until navigation).
  def versioned_serve_path(abs, folder_index, rel_path)
    kb_serve_path(src: folder_index, file: rel_path, v: (File.mtime(abs).to_f * 1000).to_i)
  end

  def file_metadata(abs, folder_index, rel_path)
    stat = File.stat(abs)
    {
      rel: rel_path,
      src: folder_index,
      filename: File.basename(abs),
      private_project: Kb::Privacy.private?(File.expand_path(kb_sources[folder_index][:path]), rel_path), # attach 403s here
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

  # Clears the sidebar "new download" dot; rebroadcasts only if a row changed.
  def mark_download_opened(folder_index, rel_path)
    source = kb_sources[folder_index] unless folder_index.negative?
    return unless source && rel_path.present?

    dir = File.dirname(rel_path)
    changed = @user.kb_downloads.where(status: "done", opened_at: nil,
                                       source_path: File.expand_path(source[:path]),
                                       dir: dir == "." ? "" : dir, filename: File.basename(rel_path))
                   .update_all(opened_at: Time.current)
    return if changed.zero?

    Kb::TreeBroadcaster.call(@user) # busts the tree cache itself
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
    Kb::MarkdownRenderer.render(raw)
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
