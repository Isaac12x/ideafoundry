require "test_helper"

class Kb::WebPageTest < ActiveSupport::TestCase
  BODY = "<p>#{'Relativity reshaped physics. ' * 80}</p>".freeze

  WIKI = <<~HTML.freeze
    <html><head><title>Albert Einstein - Wikipedia</title></head><body>
      <nav>menu</nav>
      <h1 id="firstHeading">Albert Einstein</h1>
      <div id="mw-content-text"><div class="mw-parser-output">
        <span class="mw-editsection">[edit]</span>
        #{BODY}
        <img data-src="//upload.wikimedia.org/e.jpg">
        <ol class="references">
          <li><span class="mw-cite-backlink">^ a b</span> "Gold Medal". RAS.
            <a class="external" href="https://ras.ac.uk/gold.pdf">pdf</a>
            <a class="external" href="https://web.archive.org/web/2021/https://ras.ac.uk/gold.pdf">Archived</a></li>
          <li>Book without a link. ISBN <a href="/wiki/Special:BookSources/123">123</a></li>
          <li>Audio <a href="https://upload.wikimedia.org/x.mp3">listen</a></li>
          <li>Dup <a href="https://ras.ac.uk/gold.pdf">again</a></li>
        </ol>
      </div></div>
    </body></html>
  HTML

  test "extracts title, reader body and references from a Wikipedia page" do
    page = Kb::WebPage.new(WIKI, "https://en.wikipedia.org/wiki/Albert_Einstein")

    assert_equal "Albert Einstein", page.title
    assert page.article?
    assert_not page.paywalled?

    assert_equal 1, page.references.size
    ref = page.references.first
    assert_equal "https://ras.ac.uk/gold.pdf", ref["url"]
    assert_equal "https://web.archive.org/web/2021/https://ras.ac.uk/gold.pdf", ref["archive"]
    assert_match(/\A"Gold Medal"\. RAS\./, ref["label"])

    html = page.reader_html
    assert_includes html, "<h1>Albert Einstein</h1>"
    assert_includes html, 'src="https://upload.wikimedia.org/e.jpg"'
    assert_not_includes html, "[edit]"
    assert_not_includes html, "menu"
  end

  test "reads Grokipedia-style #references and strips the site suffix" do
    html = <<~HTML
      <html><head><title>Albert Einstein — Grokipedia</title></head><body>
        <article>#{BODY}
          <div id="references"><h2>References</h2><ol>
            <li><a href="https://www.nobelprize.org/einstein">Einstein biographical</a></li>
            <li><a href="/page/Physics">internal</a></li>
          </ol></div>
        </article></body></html>
    HTML
    page = Kb::WebPage.new(html, "https://grokipedia.com/page/Albert_Einstein")

    assert_equal "Albert Einstein", page.title
    assert_equal [ "https://www.nobelprize.org/einstein" ], page.references.map { |r| r["url"] }
    assert_equal "Einstein biographical", page.references.first["label"]
  end

  test "collects links listed under a Sources heading on generic pages" do
    html = <<~HTML
      <html><body><main>#{BODY}</main>
        <h2>Sources</h2><ul><li><a href="https://example.org/a">A study</a></li></ul>
        <h2>Comments</h2><ul><li><a href="https://spam.example/x">spam</a></li></ul>
      </body></html>
    HTML
    page = Kb::WebPage.new(html, "https://blog.test/post")

    assert_equal [ "https://example.org/a" ], page.references.map { |r| r["url"] }
  end

  test "flags thin pages that declare a paywall, and hard blocks" do
    teaser = <<~HTML
      <html><head><script type="application/ld+json">{"isAccessibleForFree": false}</script></head>
      <body><article><p>First paragraph only.</p></article></body></html>
    HTML
    assert Kb::WebPage.new(teaser, "https://news.test/a").paywalled?
    assert Kb::WebPage.new("", "https://news.test/a", blocked: true).paywalled?
    assert_not Kb::WebPage.new("<p>short and free</p>", "https://x.test/").paywalled?
  end

  test "reader html credits the original URL when read from an archive" do
    page = Kb::WebPage.new("<article>#{BODY}</article>", "https://web.archive.org/web/1id_/https://news.test/a")
    html = page.reader_html(source: "https://news.test/a")

    assert_includes html, ">news.test</p>"
    assert_includes html, "via web.archive.org"
  end
end
