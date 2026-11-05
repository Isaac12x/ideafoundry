module ApplicationHelper
  EXCALIDRAW_MANIFEST_GLOB = "public/excalidraw-assets/*/manifest.json".freeze
  @excalidraw_assets = {}

  class << self
    attr_reader :excalidraw_assets
    attr_accessor :excalidraw_missing_logged # warn once per process
  end

  # Entry, stylesheet and critical chunk URLs of the code-split editor build (esbuild.config.mjs writes
  # the manifest next to the hashed files in public/excalidraw-assets/<version>/). Re-read if rebuilt.
  def excalidraw_assets
    file = Dir[Rails.root.join(EXCALIDRAW_MANIFEST_GLOB)].first
    unless file
      unless ApplicationHelper.excalidraw_missing_logged
        ApplicationHelper.excalidraw_missing_logged = true
        Rails.logger.warn("Excalidraw build missing (no #{EXCALIDRAW_MANIFEST_GLOB}); run `yarn build`. Drawing editors will show an error.")
      end
      return { js: "", css: "", preload: [] }
    end

    cache = ApplicationHelper.excalidraw_assets
    mtime = File.mtime(file)
    return cache[:data] if cache[:file] == file && cache[:mtime] == mtime

    base = "/excalidraw-assets/#{File.basename(File.dirname(file))}"
    manifest = JSON.parse(File.read(file))
    data = { js: "#{base}/#{manifest['js']}", css: "#{base}/#{manifest['css']}", preload: manifest["preload"].map { |f| "#{base}/#{f}" } }
    cache.replace(file: file, mtime: mtime, data: data)
    data
  end

  def excalidraw_stimulus_values
    {
      excalidraw_bundle_url_value: excalidraw_assets[:js],
      excalidraw_stylesheet_url_value: excalidraw_assets[:css]
    }
  end

  def idea_drawings_loader_values
    {
      idea_drawings_bundle_url_value: excalidraw_assets[:js],
      idea_drawings_stylesheet_url_value: excalidraw_assets[:css],
      idea_drawings_preload_urls_value: excalidraw_assets[:preload]
    }
  end

  def topology_graph_stimulus_values
    { topology_graph_bundle_url_value: asset_path("graph/index.js") }
  end

  def format_description(text, length: 140)
    return "" if text.blank?

    lines = text.lines.map(&:chomp)
    html = ""
    list_items = []

    lines.each do |line|
      if line.match?(/\A\s*[-*]\s+/)
        list_items << line.sub(/\A\s*[-*]\s+/, "")
      else
        if list_items.any?
          html << "<ul>" + list_items.map { |li| "<li>#{ERB::Util.html_escape(li)}</li>" }.join + "</ul>"
          list_items = []
        end
        html << "<p>#{ERB::Util.html_escape(line)}</p>" if line.present?
      end
    end

    if list_items.any?
      html << "<ul>" + list_items.map { |li| "<li>#{ERB::Util.html_escape(li)}</li>" }.join + "</ul>"
    end

    sanitize(html, tags: %w[ul li p])
  end

  def format_backlog_description(build_item)
    return "" if build_item.description.blank?

    content = []
    list_items = []
    flush_list = lambda do
      next if list_items.empty?

      content << tag.ul(safe_join(list_items.map { |item| backlog_description_list_item(build_item, item) }), class: "backlog-desc-list")
      list_items = []
    end

    build_item.description.to_s.lines(chomp: true).each_with_index do |line, index|
      checklist_item = BuildItem.parse_checklist_line(line)

      if checklist_item
        list_items << checklist_item.merge(line_index: index, checklist: true)
      elsif line.match?(/\A\s*[-*]\s+/)
        list_items << { text: line.sub(/\A\s*[-*]\s+/, ""), checklist: false }
      else
        flush_list.call
        content << tag.p(line) if line.present?
      end
    end

    flush_list.call
    safe_join(content)
  end

  def idea_context_kanban_boards_json(kanban_boards)
    Array(kanban_boards).map do |board|
      {
        id: board.id,
        name: board.name,
        lists: board.lists.map do |list|
          {
            id: list.id,
            name: list.name
          }
        end
      }
    end.to_json
  end

  def idea_context_named_lists_json(named_lists)
    Array(named_lists).map do |list|
      {
        id: list.id,
        name: list.name
      }
    end.to_json
  end

  def idea_context_list_ids(idea)
    idea.idea_lists.map(&:list_id).join(",")
  end

  def ask_agent_question_threads(limit: 10)
    return [] unless @user

    @user.local_agent_question_threads(limit: limit).reverse
  end

  def ask_agent_return_path
    uri = URI.parse(request.fullpath)
    query_params = Rack::Utils.parse_nested_query(uri.query)
    query_params["ask_agent"] = "open"
    query_string = query_params.to_query

    "#{uri.path}#{query_string.present? ? "?#{query_string}" : ""}"
  rescue URI::InvalidURIError
    root_path(ask_agent: "open")
  end

  private

  def backlog_description_list_item(build_item, item)
    return tag.li(item[:text]) unless item[:checklist]

    classes = [ "backlog-checklist-item" ]
    classes << "backlog-checklist-item--done" if item[:completed]

    tag.li(class: classes.join(" ")) do
      safe_join([
        backlog_checklist_button(build_item, item),
        tag.span(item[:title], class: "backlog-checklist-title")
      ])
    end
  end

  def backlog_checklist_button(build_item, item)
    title = item[:completed] ? "Mark subitem incomplete" : "Mark subitem complete"

    button_to toggle_checklist_item_build_item_path(build_item, line: item[:line_index]),
              method: :patch,
              class: "backlog-subcheck-btn",
              disabled: build_item.completed?,
              title: title,
              data: { turbo_stream: true },
              form: { class: "backlog-subcheck-form" } do
      if item[:completed]
        raw(%(<svg width="14" height="14" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="18" height="18" rx="4" fill="var(--success)" stroke="var(--success)" stroke-width="2"/><polyline points="9 12 11.5 14.5 15.5 10" stroke="var(--bg-base)" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>))
      else
        raw(%(<svg width="14" height="14" viewBox="0 0 24 24" fill="none"><rect x="3" y="3" width="18" height="18" rx="4" stroke="var(--border-emphasis)" stroke-width="1.5"/></svg>))
      end
    end
  end

  def activity_type_label(trackable_type)
    case trackable_type
    when "Idea"        then "Ideas"
    when "List"        then "Lists"
    when "KanbanBoard" then "Boards"
    when "Topology"    then "Topologies"
    when "Settings"    then "Settings"
    else trackable_type.to_s.humanize.pluralize
    end
  end

  # DOM id for a Think-in-Images wall — idea board or the global (KB) board.
  def mood_wall_dom_id(idea)
    idea ? "mood-wall-idea-#{idea.id}" : "mood-wall-global"
  end
end
