require "test_helper"

class Kb::MarkdownRendererTest < ActiveSupport::TestCase
  def html(md) = Kb::MarkdownRenderer.render(md)

  test "converts typographic arrows in prose" do
    out = html("a -> b <- c <-> d => e --> f <=> g")
    assert_includes out, "a → b ← c ↔ d ⇒ e → f ⇔ g"
  end

  test "leaves <= and -- alone and still escapes" do
    out = html("x <= y -- z & <b>")
    assert_includes out, "x &lt;= y -- z &amp; "
    assert_no_match(/[→←⇒]/, out)
  end

  test "does not touch code, fences or urls" do
    out = html("`a->b`\n\n```\nc=>d\n```\n\nhttp://x.com/a->b")
    assert_includes out, "<code>a-&gt;b</code>"
    assert_includes out, "c=&gt;d"
    assert_includes out, 'href="http://x.com/a-%3Eb"'
  end

  test "mermaid and alias fences become kb-diagram hosts with escaped source" do
    out = html("```mermaid\nA-->B<script>\n```\n\n```flowchart\nA-->B\n```")
    assert_equal 2, out.scan('data-controller="kb-diagram"').size
    assert_includes out, "A--&gt;B&lt;script&gt;"
    assert_includes out, 'data-kb-diagram-keyword-value="flowchart"'
    assert_no_match(/→/, out)
  end

  test "diagram hosts survive blockquotes, tilde fences and uppercase languages" do
    out = html("> ```mermaid\n> A-->B\n> ```\n\n~~~mermaid\nC-->D\n~~~\n\n```MERMAID\nE-->F\n```")
    assert_equal 3, out.scan('data-controller="kb-diagram"').size
    assert_match(%r{<blockquote>\s*<div class="kb-diagram"}, out)
    assert_includes out, "C--&gt;D"
    assert_no_match(/kbdiagram/, out)
  end

  test "graphviz and plantuml show source with a note, other fences are stock" do
    out = html("```dot\ndigraph{a->b}\n```\n\n```ruby\nx\n```")
    assert_includes out, "kb-diagram-unsupported"
    assert_includes out, "dot diagram not rendered: drawing it would need an outside service"
    assert_includes out, "a-&gt;b"
    assert_includes out, "<pre><code class=\"ruby\">x\n</code></pre>"
  end

  test "raw html scripts, handlers and javascript links are stripped" do
    out = html("<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n\n[x](javascript:alert(1))\n\n<a href=\"javascript:alert(2)\">y</a>")
    assert_no_match(/<script|onerror|javascript:/i, out)
  end

  test "sanitizing keeps tables, inline html, links and arrows" do
    out = html("| a | b |\n|---|---|\n| 1 | 2 |\n\n<details><summary>s</summary><kbd>k</kbd></details>\n\n[l](http://x.com) a->b")
    assert_includes out, "<table>"
    assert_includes out, "<details><summary>s</summary><kbd>k</kbd></details>"
    assert_includes out, 'target="_blank"'
    assert_includes out, "a→b"
  end

  test "forged diagram attributes in raw html are removed but real hosts survive" do
    out = html("<div data-controller=\"kb-diagram\" data-kb-diagram-url-value=\"//evil/x.js\">x</div>\n\n```mermaid\nA-->B\n```")
    assert_no_match(/evil/, out)
    assert_equal 1, out.scan('data-controller="kb-diagram"').size
    assert_includes out, "A--&gt;B"
  end

  test "script and style bodies are dropped, not shown as text" do
    out = html("hi\n\n<script>alert(1)</script>\n\n<style>p{color:red}</style>\n\nbye")
    assert_includes out, "hi"
    assert_includes out, "bye"
    assert_no_match(/alert|color:red|<script|<style/, out)
  end
end
