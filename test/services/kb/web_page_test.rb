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

  WIKI_LIVE = <<~HTML.freeze
    <html lang="en"><head><title>Ada - Wikipedia</title></head><body>
      <div id="mw-sidebar">sidebar</div><div class="vector-header">search</div>
      <h1 id="firstHeading">Ada Lovelace</h1>
      <div id="mw-content-text"><div class="mw-parser-output">
        <div class="hatnote">For other uses, see Ada.</div>
        <span class="shortdescription" style="display:none">English mathematician</span>
        <table class="infobox"><tr><th class="infobox-label">Born</th><td>1815</td></tr></table>
        <div class="mw-heading mw-heading2"><h2 id="Life">Life</h2><span class="mw-editsection">[edit]</span></div>
        #{BODY}
        <figure typeof="mw:File/Thumb"><img src="//upload.wikimedia.org/a.jpg" width="220" height="300"><figcaption>Ada c. 1843</figcaption></figure>
        <p>Cite<sup id="cite_ref-1" class="reference"><a href="#cite_note-1">[1]</a></sup></p>
        <div class="printfooter">Retrieved from</div><div class="catlinks">Categories</div>
      </div></div></body></html>
  HTML

  test "detects Wikipedia hosts but not other wiki-family or lookalike hosts" do
    assert Kb::WebPage.new("", "https://en.wikipedia.org/wiki/X").wikipedia?
    assert Kb::WebPage.new("", "https://de.m.wikipedia.org/wiki/X").wikipedia?
    assert_not Kb::WebPage.new("", "https://commons.wikimedia.org/wiki/X").wikipedia?
    assert_not Kb::WebPage.new("", "https://notwikipedia.org/wiki/X").wikipedia?
    assert_not Kb::WebPage.new("", "https://wikipedia.org.evil.test/").wikipedia?
  end

  test "wikipedia pages get the wikipedia stylesheet and keep infobox/thumb markup, minus chrome" do
    html = Kb::WebPage.new(WIKI_LIVE, "https://en.wikipedia.org/wiki/Ada_Lovelace").reader_html
    css, html = html.split("</style>")

    assert_includes html, "From Wikipedia, the free encyclopedia"
    assert_includes css, "table.infobox"
    assert_includes css, "Linux Libertine"
    assert_includes html, '<table class="infobox">'
    assert_includes html, "For other uses, see Ada."
    assert_includes html, "Ada c. 1843"
    assert_includes html, 'src="https://upload.wikimedia.org/a.jpg"'
    assert_includes html, 'href="#cite_note-1"' # footnote anchors stay in-page
    assert_includes html, 'id="cite_ref-1"'
    %w[sidebar search [edit] English\ mathematician Retrieved Categories].each { |junk| assert_not_includes html, junk }
  end

  test "non-wikipedia pages use the generic reader stylesheet" do
    html = Kb::WebPage.new("<article>#{BODY}</article>", "https://blog.test/p").reader_html

    assert_includes html, ".kicker"
    assert_not_includes html, "Linux Libertine"
    assert_not_includes html, "From Wikipedia"
  end

  test "cleanup drops cookie banners, ads and hidden nodes, and resolves lazy images" do
    html = <<~HTML
      <article>#{BODY}
        <div class="cookie-banner">Accept cookies</div>
        <div class="ad">Buy</div><div role="dialog">Sign up</div>
        <p style="display: none">hidden text</p>
        <img src="data:image/gif;base64,R0" data-src="/img/a.jpg">
        <img srcset="/s.jpg 400w, /l.jpg 1200w">
        <a href="/rel">rel</a><a href="#note">note</a>
      </article>
    HTML
    out = Kb::WebPage.new(html, "https://blog.test/p/1").reader_html

    %w[cookies Buy Sign\ up hidden\ text].each { |junk| assert_not_includes out, junk }
    assert_includes out, 'src="https://blog.test/img/a.jpg"'
    assert_includes out, 'src="https://blog.test/l.jpg"'
    assert_includes out, 'href="https://blog.test/rel"'
    assert_includes out, 'href="#note"'
  end

  test "falls back to loose text on <p>-less pages" do
    loose = "<html><body><table><tr><td><font>#{'Plain old essay text. ' * 120}<br><br>More.</font></td></tr></table></body></html>"
    page = Kb::WebPage.new(loose, "https://old.test/essay.html")

    assert page.article?
  end

  test "heading anchors unwrap, br runs collapse, stray infobox br go, math images survive" do
    html = <<~HTML
      <article><h2><a href="#x">1. Intro</a></h2>#{BODY}
        <p>one<br><br><br><br><br>two</p>
        <table><tr><td><div>Name</div><br>1815<br><div>London</div></td></tr></table>
        <p><span aria-hidden="true">chrome</span>
        <img class="mwe-math-fallback-image-inline" aria-hidden="true" style="width:1ex" src="/m.svg"></p>
      </article>
    HTML
    out = Kb::WebPage.new(html, "https://blog.test/p").reader_html

    assert_includes out, "<h2>1. Intro</h2>"
    assert_includes out, "one<br><br>two"
    assert_includes out, "<div>Name</div>1815<div>London</div>"
    assert_not_includes out, "chrome</span>"
    assert_includes out, 'style="width:1ex"'
  end

  test "print css carries a running footer with the short title, not on the first page" do
    out = Kb::WebPage.new("<article>#{BODY}</article>", "https://blog.test/p").reader_html

    assert_includes out, "@bottom-right { content: counter(page); }"
    assert_includes out, "@page :first { @bottom-left { content: none; } }"
    assert_includes out, "hyphens: auto"
  end
end
