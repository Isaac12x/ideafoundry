require "open-uri"
require "json"

module Kb
  # Reader-mode view of a web page (Wikipedia, Grokipedia, articles): pulls the
  # main content out of the chrome, collects the page's reference list, and
  # spots paywalls so KbDownloadJob can go looking for an archived copy.
  class WebPage
    UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " \
         "(KHTML, like Gecko) Version/17.0 Safari/605.1.15".freeze
    MAX_BYTES = 15.megabytes
    BLOCKED_STATUSES = %w[401 402 403 451].freeze
    MIN_ARTICLE_CHARS = 1_500

    ROOT_SELECTORS = [
      "#mw-content-text .mw-parser-output", "article", "[role=main]", "main",
      ".post-content", ".entry-content", "#content"
    ].freeze
    JUNK_SELECTORS = %w[
      script style noscript iframe form button input select textarea nav aside
      footer template link meta svg [hidden]
      [aria-hidden=true]:not(.mwe-math-fallback-image-inline):not(.mwe-math-fallback-image-display)
      .mw-editsection .mw-jump-link .navbox .vertical-navbox .sistersitebox
      .noprint .mw-empty-elt #toc .toc .metadata .ambox
      .mw-authority-control .printfooter .catlinks .mw-indicators .shortdescription #siteSub #contentSub
      .mw-collapsible-toggle .sr-only .visually-hidden
      [role=banner] [role=navigation] [role=complementary] [role=dialog] [aria-modal=true]
      [style*='display:none'] [style*='visibility:hidden']
      [class~=ad] [class~=ads] [class~=advert] [class~=advertisement] [class~=sponsored] [id^=google_ads]
      [class*=cookie] [id*=cookie] [class*=consent] [id*=consent] [class*=newsletter] [class*=social-share]
      [class*=share-buttons] [class*=related-posts] [class*=breadcrumb] [id=comments] [class~=comments]
    ].join(", ").freeze
    # class/id/width/height keep Wikipedia's markup stylable and footnote anchors alive.
    KEEP_ATTRS = %w[href src alt title colspan rowspan class id width height lang typeof].freeze
    WIKIPEDIA = /(\A|\.)wikipedia\.org\z/i
    LAZY_SRC = %w[data-src data-lazy-src data-original].freeze
    REFERENCE_HEADING = /\A\s*(references|sources|citations|notes|bibliography|works cited|footnotes)\s*\z/i
    REFERENCE_LISTS = "ol.references > li, #references li, .reflist li, .refbegin li".freeze
    WIKI_FAMILY = /(\A|\.)(wikipedia|wikimedia|wikisource|wikidata|wikiquote|wiktionary|wikibooks|mediawiki)\.org\z/i
    ARCHIVE_HOSTS = /(\A|\.)(web\.archive\.org|archive\.org|archive\.ph|archive\.today|archive\.is)\z/i
    PAYWALL_MARKERS = /paywall|subscribe to (continue|read)|subscriber[- ]only|already a subscriber|
                       create a free account to (continue|read)|piano-?(id|offer)|tp-modal/xi

    # nil when the URL isn't an HTML page (PDF, media...): caller downloads it raw.
    def self.fetch(url)
      URI.parse(url).open("User-Agent" => UA, "Accept" => "text/html,application/xhtml+xml",
                          "Accept-Language" => "en", open_timeout: 15, read_timeout: 30) do |io|
        return nil unless io.content_type.to_s.match?(/html/i)
        new(io.read(MAX_BYTES).to_s, io.base_uri.to_s)
      end
    rescue OpenURI::HTTPError => e
      raise unless BLOCKED_STATUSES.include?(e.io.status.first.to_s)
      new("", url, blocked: true)
    end

    # Archived copies to try for a paywalled URL: the citation's own archive
    # link, the Wayback Machine's closest snapshot (raw, no toolbar), then
    # archive.today. Mirrors the lifehacker "archive site" technique.
    def self.archive_candidates(url, known_archive = nil)
      list = [ known_archive.presence ]
      list << wayback_snapshot(url)
      list << "https://archive.ph/newest/#{url}"
      list.compact.uniq
    end

    def self.wayback_snapshot(url)
      api = "https://archive.org/wayback/available?url=#{CGI.escape(url)}"
      snap = JSON.parse(URI.parse(api).open("User-Agent" => UA, read_timeout: 20).read)
                 .dig("archived_snapshots", "closest")
      return nil unless snap&.dig("available") && snap["timestamp"].present?
      "https://web.archive.org/web/#{snap['timestamp']}id_/#{url}"
    rescue StandardError
      nil
    end

    # Ask the Wayback Machine to snapshot the page; the job retries later.
    def self.request_archive(url)
      URI.parse("https://web.archive.org/save/#{url}").open("User-Agent" => UA, read_timeout: 60, &:read)
      true
    rescue StandardError
      false
    end

    attr_reader :url, :html

    def initialize(html, url, blocked: false)
      @html = html
      @url = url
      @blocked = blocked
      @doc = Nokogiri::HTML(html)
    end

    def title
      @title ||= [
        @doc.at_css("#firstHeading")&.text,
        @doc.at_css("meta[property='og:title']")&.[]("content"),
        @doc.at_css("h1")&.text,
        @doc.title
      ].map { |t| without_site_suffix(t.to_s.squish) }.find(&:present?) || host
    end

    def host = URI.parse(url).host.to_s.delete_prefix("www.")

    # Any *.wikipedia.org page (not the wider WIKI_FAMILY): gets Wikipedia's look.
    def wikipedia? = host.match?(WIKIPEDIA)

    def text_length = article&.text.to_s.squish.length

    def article? = text_length >= MIN_ARTICLE_CHARS

    # Hard block (401/402/403) or a thin page that says "subscribe".
    def paywalled?
      return true if @blocked
      return false if article?
      free = @html[/"isAccessibleForFree"\s*:\s*"?(false|true)/i, 1]
      free&.casecmp?("false") || @html.match?(PAYWALL_MARKERS)
    end

    # [{ "url", "label", "archive" }] — only entries with an external link.
    def references
      @references ||= reference_items.filter_map { |li| reference_from(li) }.uniq { |r| r["url"] }
    end

    # Standalone reader document (Safari Reader-style) ready to print to PDF.
    # source: the original URL when this page came from an archive.
    def reader_html(source: url, fetched_at: Time.current)
      body = article&.inner_html.to_s
      site = URI.parse(source).host.to_s.delete_prefix("www.")
      h = ERB::Util.method(:h)
      meta = %(<a href="#{h[source]}">#{h[source]}</a>#{" · via #{h[host]}" if source != url} · retrieved #{fetched_at.strftime('%-d %B %Y')})
      head = if wikipedia?
        tagline = host.start_with?("en.") || host.start_with?("simple.") ? %(<p class="tagline">From Wikipedia, the free encyclopedia</p>) : ""
        %(<header class="wp-head"><h1>#{h[title]}</h1>#{tagline}<p class="source">#{meta}</p></header>)
      else
        %(<header><p class="kicker">#{h[site]}</p><h1>#{h[title]}</h1><p class="source">#{meta}</p></header>)
      end
      <<~HTML
        <!doctype html>
        <html lang="#{h[@doc.at_css('html')&.[]('lang').presence || 'en']}"><head><meta charset="utf-8">
        <title>#{h[title]}</title>
        <style>#{wikipedia? ? ReaderStyles::WIKIPEDIA : ReaderStyles::READER}
        #{ReaderStyles.footer(title)}</style></head>
        <body><main>
          #{head}
          <div class="mw-parser-output">#{body}</div>
        </main></body></html>
      HTML
    end

    private

    def article
      return @article if defined?(@article)
      node = ROOT_SELECTORS.lazy.map { |sel| @doc.at_css(sel) }.find { |n| n && n.text.squish.length > 500 }
      node ||= densest_block
      @article = node && clean(node.dup)
    end

    # Fallback: the element holding the most paragraph text; for <br>-and-<font>
    # era pages (no <p>s) the element with the most loose text of its own.
    def densest_block
      best = @doc.css("p").group_by(&:parent).max_by { |_, ps| ps.sum { |p| p.text.length } }&.first
      return best if best && best.text.squish.length >= MIN_ARTICLE_CHARS
      loose = @doc.css("td, div, font, section, body").max_by { |n| n.xpath("./text()").sum { |t| t.text.squish.length } }
      loose && loose.text.squish.length > (best&.text.to_s.squish.length || 0) ? loose : best
    end

    def clean(node)
      node.css(JUNK_SELECTORS).remove
      node.css("[style]").each { |n| n.remove if n["style"].match?(/display:\s*none|visibility:\s*hidden/i) }
      node.css("h1, h2").each { |h| h.remove if h.text.squish == title }
      # Heading anchors (Rails guides, Substack...) are chrome, not links.
      node.css("h1 a, h2 a, h3 a, h4 a, h5 a, h6 a").each { |a| a.replace(a.children) }
      tidy_breaks(node)
      node.css("img").each do |img|
        src = LAZY_SRC.filter_map { |a| img[a].presence }.first || img["src"].presence || biggest_srcset(img["data-srcset"] || img["srcset"])
        src.present? ? img["src"] = absolute(src) : img.remove
      end
      node.css("a[href]").each { |a| a["href"] = absolute(a["href"]) unless a["href"].start_with?("#") }
      node.traverse do |n|
        next unless n.element?
        # math fallback images carry their size (in ex) only in style.
        keep = n["class"].to_s.include?("mwe-math-fallback") ? KEEP_ATTRS + %w[style] : KEEP_ATTRS
        n.attribute_nodes.each { |attr| attr.remove unless keep.include?(attr.name) }
      end
      node
    end

    BLOCKS = %w[div p ul ol dl table blockquote h1 h2 h3 h4 h5 h6 pre figure].freeze

    # <br> runs (spacer gaps on <br>-era pages) collapse to one blank line; a <br>
    # touching a block or a cell edge only adds stray space (infobox "Born" rows).
    def tidy_breaks(node)
      node.css("br").each do |br|
        prev = br.previous_sibling
        prev = prev.previous_sibling while prev&.text? && prev.text.blank?
        nxt = br.next_sibling
        nxt = nxt.next_sibling while nxt&.text? && nxt.text.blank?
        next br.remove if prev.nil? || nxt.nil? || BLOCKS.include?(prev.name) || BLOCKS.include?(nxt.name)
        br.remove if prev.name == "br" && nxt.name == "br"
      end
    end

    # "a.jpg 1x, b.jpg 2x" / "a.jpg 400w, b.jpg 800w" -> the largest candidate's URL.
    def biggest_srcset(set)
      set.to_s.split(",").map { |c| c.split }.select(&:any?).max_by { |u, d| d.to_f }&.first
    end

    def reference_items
      items = @doc.css(REFERENCE_LISTS).to_a
      @doc.css("h2, h3").each do |h|
        next unless h.text.match?(REFERENCE_HEADING)
        # Wikipedia wraps headings in div.mw-heading; walk that wrapper's siblings.
        start = h.parent&.[]("class").to_s.include?("mw-heading") ? h.parent : h
        sib = start.next_element
        while sib && !sib.matches?("h2, .mw-heading2") && sib.at_css("h2").nil?
          items.concat(sib.css("li").to_a)
          sib = sib.next_element
        end
      end
      items.uniq
    end

    def reference_from(li)
      li = li.dup
      li.css(".mw-cite-backlink, sup, style").remove
      links = li.css("a[href]").filter_map { |a| external(a["href"]) }
      archive = links.find { |l| archive_host?(l) }
      primary = links.find { |l| !archive_host?(l) } || archive
      return nil unless primary

      label = li.text.squish.presence || primary
      { "url" => primary, "label" => label.truncate(240), "archive" => (archive if archive != primary) }
    end

    # "Albert Einstein — Grokipedia" -> "Albert Einstein"
    def without_site_suffix(text)
      site = host.split(".").first(2).find { |part| part.length > 3 }.to_s
      head, sep, tail = text.rpartition(/\s+[—–|-]\s+/)
      sep.present? && head.present? && site.present? && tail.downcase.delete(" ").include?(site) ? head : text
    end

    def external(href)
      abs = absolute(href)
      uri = URI.parse(abs)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
      link_host = uri.host.delete_prefix("www.")
      return nil if link_host == host
      # Wikipedia -> Wikimedia/Wikisource links are sister-project chrome, not citations.
      return nil if link_host.match?(WIKI_FAMILY) && host.match?(WIKI_FAMILY)
      abs
    rescue URI::InvalidURIError
      nil
    end

    def archive_host?(link) = URI.parse(link).host.to_s.match?(ARCHIVE_HOSTS)

    def absolute(href)
      URI.join(url, href.to_s.strip).to_s
    rescue URI::Error, ArgumentError
      href.to_s
    end
  end
end
