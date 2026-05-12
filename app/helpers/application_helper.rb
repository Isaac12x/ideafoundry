module ApplicationHelper
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

  private

  def backlog_description_list_item(build_item, item)
    return tag.li(item[:text]) unless item[:checklist]

    classes = ["backlog-checklist-item"]
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
end
