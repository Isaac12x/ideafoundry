class KbController < ApplicationController
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

    @content_html = render_file(@selected_folder_index, @selected_file)
    @facts = @user.facts.recent
  end

  def file
    folder_index = params[:src].to_i
    rel_path = params[:file]
    @content_html = render_file(folder_index, rel_path)
    @selected_file = rel_path
    @selected_folder_index = folder_index
  end

  private

  def build_folder_tree
    @user.kb_folders.each_with_index.map do |path, idx|
      expanded = File.expand_path(path)
      files = []
      if Dir.exist?(expanded)
        files = Dir.glob(File.join(expanded, "**", "*.md"))
                   .sort
                   .map { |f| { rel: f.sub("#{expanded}/", ""), abs: f } }
      end
      tree = build_nested_tree(files)
      { index: idx, path: path, label: File.basename(path), files: files, tree: tree, exists: Dir.exist?(expanded) }
    end
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

    folders = @user.kb_folders
    return nil if folder_index >= folders.size

    base = File.expand_path(folders[folder_index])
    abs = File.expand_path(File.join(base, rel_path))

    # Security: ensure the resolved path is within the configured folder
    return nil unless abs.start_with?(base + "/") || abs == base
    return nil unless File.exist?(abs) && abs.end_with?(".md")

    raw = File.read(abs)
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
