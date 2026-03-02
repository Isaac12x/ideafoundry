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
end
