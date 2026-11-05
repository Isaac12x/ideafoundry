# Shared Markdown -> HTML for every KB surface. Typographic arrows are applied to
# prose text nodes only: Redcarpet never sends code spans, fenced blocks, URLs or
# raw HTML (tags/attributes) through #normal_text.
module Kb
  class MarkdownRenderer < Redcarpet::Render::HTML
    # Order matters: longest/bidirectional forms first. `<=` is left alone (comparison).
    ARROWS = [
      [ /<=>/, "⇔" ],
      [ /<-{1,2}>/, "↔" ],
      [ /<-{1,2}(?![\d>-])/, "←" ],
      [ /-{1,2}>/, "→" ],
      [ /=>/, "⇒" ]
    ].freeze

    # Fence language -> Mermaid keyword that must open the source. mermaid itself needs none.
    DIAGRAM_LANGS = {
      "mermaid" => nil, "flowchart" => "flowchart", "sequencediagram" => "sequenceDiagram",
      "gantt" => "gantt", "classdiagram" => "classDiagram", "statediagram" => "stateDiagram-v2",
      "erdiagram" => "erDiagram", "journey" => "journey", "mindmap" => "mindmap",
      "timeline" => "timeline", "pie" => "pie"
    }.freeze
    # No local renderer for these; shown as code with a note (no network renderers).
    UNSUPPORTED_DIAGRAMS = %w[dot graphviz plantuml].freeze

    # Untrusted markdown (files, note sidecars) may carry raw HTML: sanitize everything, keeping the
    # tags Markdown itself produces plus the inline HTML people already use. javascript: URLs, scripts
    # and on* handlers are stripped. Diagram hosts carry data-controller/url values, so they never go
    # through the sanitizer: block_code emits a nonce placeholder that is swapped in afterwards.
    ALLOWED_TAGS = %w[a abbr b blockquote br code dd del details div dl dt em figcaption figure h1 h2 h3 h4 h5 h6 hr i img ins kbd
                      li mark ol p pre s small span strike strong sub summary sup table tbody td tfoot th thead tr u ul].freeze
    ALLOWED_ATTRIBUTES = %w[href src alt title class target rel colspan rowspan align open width height].freeze

    def self.render(raw)
      renderer = new(hard_wrap: true, link_attributes: { target: "_blank", rel: "noopener" })
      md = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, strikethrough: true, no_intra_emphasis: true)
      # sanitize strips <script>/<style> tags but keeps their text; drop the elements whole first.
      fragment = Loofah.fragment(md.render(raw.to_s)).tap { |f| f.css("script, style").remove }
      html = ActionController::Base.helpers.sanitize(fragment.to_s, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
      renderer.hosts.each { |token, host| html = html.sub("<p>#{token}</p>") { host } }
      html.html_safe
    end

    def hosts = (@hosts ||= {})

    # ```mermaid (and aliases) become a kb-diagram Stimulus host that lazy-loads mermaid.
    # Everything else keeps Redcarpet's stock <pre><code class="lang"> shape.
    def block_code(code, language)
      lang = language.to_s.strip.split(/[\s{]/).first.to_s.downcase
      src = ERB::Util.html_escape(code)
      if DIAGRAM_LANGS.key?(lang)
        url = ActionController::Base.helpers.asset_path("mermaid_app/index.js")
        token = "kbdiagram#{@nonce ||= SecureRandom.hex(8)}n#{hosts.size}"
        hosts[token] = %(<div class="kb-diagram" data-controller="kb-diagram" data-kb-diagram-url-value="#{ERB::Util.html_escape(url)}" ) +
          %(data-kb-diagram-keyword-value="#{DIAGRAM_LANGS[lang]}"><pre class="kb-diagram-src"><code>#{src}</code></pre></div>\n)
        "<p>#{token}</p>\n"
      elsif UNSUPPORTED_DIAGRAMS.include?(lang)
        %(<figure class="kb-diagram-unsupported"><figcaption>#{ERB::Util.html_escape(lang)} diagram not rendered: drawing it would need an outside service. Source shown.</figcaption>) +
          %(<pre><code class="#{lang}">#{src}</code></pre></figure>\n)
      else
        cls = lang.empty? ? "" : %( class="#{ERB::Util.html_escape(lang)}")
        "<pre><code#{cls}>#{src}</code></pre>\n"
      end
    end

    # Overriding normal_text bypasses Redcarpet's own escaping, so escape here.
    def normal_text(text)
      ERB::Util.html_escape(ARROWS.reduce(text) { |t, (re, glyph)| t.gsub(re, glyph) })
    end
  end
end
