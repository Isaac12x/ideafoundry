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
      footer template link meta svg [hidden] [aria-hidden=true]
      .mw-editsection .mw-jump-link .navbox .vertical-navbox .sistersitebox
      .noprint .mw-empty-elt #toc .toc .metadata .ambox
    ].join(", ").freeze
    KEEP_ATTRS = %w[href src alt title colspan rowspan].freeze
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
      <<~HTML
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <title>#{ERB::Util.h(title)}</title>
        <style>#{READER_CSS}</style></head>
        <body><main>
          <header>
            <p class="kicker">#{ERB::Util.h(site)}</p>
            <h1>#{ERB::Util.h(title)}</h1>
            <p class="source"><a href="#{ERB::Util.h(source)}">#{ERB::Util.h(source)}</a>#{" · via #{ERB::Util.h(host)}" if source != url} · retrieved #{fetched_at.strftime('%-d %B %Y')}</p>
          </header>
          #{body}
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

    # Fallback: the element holding the most paragraph text.
    def densest_block
      @doc.css("p").group_by(&:parent).max_by { |_, ps| ps.sum { |p| p.text.length } }&.first
    end

    def clean(node)
      node.css(JUNK_SELECTORS).remove
      node.css("h1").each { |h| h.remove if h.text.squish == title }
      node.css("img").each do |img|
        src = img["data-src"].presence || img["src"]
        src.present? ? img["src"] = absolute(src) : img.remove
      end
      node.css("a[href]").each { |a| a["href"] = absolute(a["href"]) }
      node.traverse do |n|
        next unless n.element?
        n.attribute_nodes.each { |attr| attr.remove unless KEEP_ATTRS.include?(attr.name) }
      end
      node
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

    READER_CSS = <<~CSS.freeze
      @page { size: A4; margin: 22mm 20mm 24mm; }
      html { -webkit-print-color-adjust: exact; }
      body { margin: 0; color: #1f1b16;
             font: 11.5pt/1.62 "Iowan Old Style", Charter, "Palatino Linotype", Georgia, serif; }
      main { max-width: 38em; margin: 0 auto; padding: 2.5em 0; }
      header { border-bottom: 0.5pt solid #d9cfbf; margin-bottom: 2em; padding-bottom: 1.2em; }
      .kicker { font: 600 8pt/1 -apple-system, "Helvetica Neue", sans-serif; letter-spacing: .16em;
                text-transform: uppercase; color: #a0672a; margin: 0 0 1em; }
      h1 { font-size: 26pt; line-height: 1.1; font-weight: 600; margin: 0 0 .5em; letter-spacing: -.01em; }
      .source { font-size: 8.5pt; color: #7d7263; margin: 0; word-break: break-all; }
      .source a { color: inherit; }
      h2 { font-size: 16pt; margin: 1.8em 0 .5em; break-after: avoid; }
      h3, h4 { font-size: 12.5pt; margin: 1.4em 0 .4em; break-after: avoid; }
      p, li { orphans: 3; widows: 3; }
      a { color: #8a5320; text-decoration: none; }
      img { max-width: 100%; height: auto; break-inside: avoid; }
      figure, tr { break-inside: avoid; }
      figure { margin: 1.4em 0; } figcaption { font-size: 9pt; color: #7d7263; }
      table { border-collapse: collapse; font-size: 9.5pt; margin: 1.2em 0; max-width: 100%; }
      th, td { border-bottom: 0.5pt solid #e4dccf; padding: .3em .5em; vertical-align: top; text-align: left; }
      blockquote { margin: 1.2em 0; padding-left: 1em; border-left: 2pt solid #d9cfbf; color: #4d443a; }
      pre, code { font-size: 9pt; white-space: pre-wrap; }
      sup { font-size: 7pt; line-height: 0; }
      ol.references, #references ol { font-size: 9pt; }
    CSS
  end
end
