class KbController < ApplicationController
  NATIVE_KB_PATH = Rails.root.join("docs", "kb").to_s.freeze
  NATIVE_KB_LABEL = "App KB".freeze

  # Extensions surfaced in the KB tree. Markdown renders inline; the rest are
  # converted to HTML and shown in a sandboxed iframe via the +raw+ action.
  MARKDOWN_EXTENSIONS = %w[.md].freeze
  EMBED_EXTENSIONS = %w[.html .htm .docx .xlsx].freeze
  KB_EXTENSIONS = (MARKDOWN_EXTENSIONS + EMBED_EXTENSIONS).freeze

  # Locked-down CSP for embedded documents: no scripts, no network access,
  # only inline styles and data: images/fonts (pandoc inlines media as data URIs).
  EMBED_CSP = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:".freeze

  KbContent = Struct.new(:kind, :html, :raw_url, keyword_init: true)

  before_action :set_user

  def index
    @folders = build_folder_tree
    @selected_file = params[:file]
    @selected_folder_index = params[:src].to_i

    if @selected_file.blank? && @folders.any?
      first_folder = @folders.first
      first_file = first_folder[:files].first
      if first_file
        @selected_file = first_file[:rel]
        @selected_folder_index = 0
      end
    end

    @content = render_file(@selected_folder_index, @selected_file)
    @facts = @user.facts.recent
    @maxims = @user.maxims.recent
  end

  def file
    folder_index = params[:src].to_i
    rel_path = params[:file]
    @content = render_file(folder_index, rel_path)
    @selected_file = rel_path
    @selected_folder_index = folder_index
  end

  # Serves an embeddable document (html/docx/xlsx) as a standalone HTML body
  # for consumption inside a sandboxed iframe. Markdown is never served here.
  def raw
    abs = resolve_kb_path(params[:src].to_i, params[:file], extensions: EMBED_EXTENSIONS)
    return head(:not_found) if abs.nil?

    html = KbDocumentRenderer.new(abs).to_html
    response.set_header("Content-Security-Policy", EMBED_CSP)
    render html: html.html_safe, layout: false, content_type: "text/html"
  rescue KbDocumentRenderer::ConversionError
    head :unprocessable_entity
  end

  private

  def build_folder_tree
    kb_sources.each_with_index.map do |source, idx|
      path = source[:path]
      expanded = File.expand_path(path)
      files = []
      if Dir.exist?(expanded)
        files = Dir.glob(File.join(expanded, "**", "*"))
                   .select { |f| File.file?(f) && KB_EXTENSIONS.include?(File.extname(f).downcase) }
                   .sort
                   .map { |f| { rel: f.sub("#{expanded}/", ""), abs: f } }
      end
      tree = build_nested_tree(files)
      {
        index: idx,
        path: path,
        label: source[:label] || folder_label(path),
        files: files,
        tree: tree,
        exists: Dir.exist?(expanded),
        native: source[:native]
      }
    end
  end

  def kb_sources
    native_kb_sources + @user.kb_folders.map do |path|
      { path: path, label: folder_label(path), native: false }
    end
  end

  def native_kb_sources
    return [] unless Dir.exist?(NATIVE_KB_PATH)
    return [] if Dir.glob(File.join(NATIVE_KB_PATH, "**", "*.md")).empty?

    [{ path: NATIVE_KB_PATH, label: NATIVE_KB_LABEL, native: true }]
  end

  def folder_label(path)
    File.basename(path.to_s.chomp(File::SEPARATOR)).presence || path.to_s
  end

  def build_nested_tree(files)
    root = {}
    files.each do |file|
      parts = file[:rel].split("/")
      current = root
      parts[0..-2].each do |dir|
        current[dir] ||= { type: :dir, children: {} }
        current = current[dir][:children]
      end
      current[parts.last] = { type: :file, rel: file[:rel], abs: file[:abs] }
    end
    root
  end

  def render_file(folder_index, rel_path)
    return nil if rel_path.blank?

    abs = resolve_kb_path(folder_index, rel_path)
    return KbContent.new(kind: :missing) if abs.nil?

    ext = File.extname(abs).downcase
    if MARKDOWN_EXTENSIONS.include?(ext)
      KbContent.new(kind: :markdown, html: render_markdown(File.read(abs)))
    elsif EMBED_EXTENSIONS.include?(ext)
      KbContent.new(kind: :embed, raw_url: kb_raw_path(src: folder_index, file: rel_path))
    else
      KbContent.new(kind: :missing)
    end
  end

  # Resolves a folder-relative path to an absolute path, rejecting anything that
  # escapes the configured folder or has an unsupported extension.
  def resolve_kb_path(folder_index, rel_path, extensions: KB_EXTENSIONS)
    return nil if rel_path.blank?

    sources = kb_sources
    return nil if folder_index.negative? || folder_index >= sources.size

    base = File.expand_path(sources[folder_index][:path])
    abs = File.expand_path(File.join(base, rel_path))

    # Security: ensure the resolved path stays within the configured folder
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
