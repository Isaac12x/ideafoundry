# Rich-text (ActionText HTML) descriptions often hold markdown typed as plain text: `***bold***`,
# ``` fences, lists. Runs of plain <p>/<div> blocks that look like markdown are re-rendered through
# Kb::MarkdownRenderer (sanitized); headings, lists, images and attachments are left untouched.
# ponytail: fence bodies keep HTML entities from the editor (&lt; shows literally); decode if it bites.
module Kb
  module RichProse
    PLAIN = %w[br strong b em i code span a].freeze
    MARKDOWN = /[*_`#>~\[]|^\s*(?:[-+]|\d+\.)\s/

    def self.call(html)
      frag = Nokogiri::HTML5.fragment(html.to_s)
      roots = frag.css("div.trix-content").to_a.presence || [ frag ]
      roots.each { |root| convert(root) }
      frag.to_html.html_safe
    end

    def self.convert(root)
      run = []
      flush = lambda do
        text = run.map { |n| n.inner_html.gsub(%r{<br\s*/?>}i, "\n") }.join("\n\n")
        if text.match?(MARKDOWN)
          run.first.add_previous_sibling(Kb::MarkdownRenderer.render(text.gsub("&nbsp;", " ")).to_s)
          run.each(&:remove)
        end
        run = []
      end
      root.children.to_a.each do |n|
        if plain_block?(n) then run << n
        elsif n.text? && n.text.strip.empty? then next
        else flush.call
        end
      end
      flush.call
    end

    def self.plain_block?(node)
      node.element? && %w[p div].include?(node.name) && node.css("*").all? { |e| PLAIN.include?(e.name) }
    end
  end
end
