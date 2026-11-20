require "test_helper"

class Kb::RichProseTest < ActiveSupport::TestCase
  test "plain paragraphs holding markdown are rendered" do
    out = Kb::RichProse.call(%(<div class="trix-content"><div>***HIL***</div><div>```<br>a = 1<br>```</div></div>))
    assert_includes out, "<strong><em>HIL</em></strong>"
    assert_includes out, "<pre><code>a = 1"
    assert_includes out, 'class="trix-content"'
  end

  test "structured html and plain text are left alone, xss stripped" do
    html = %(<div class="trix-content"><div>hello</div><ul><li>x*y</li></ul></div>)
    assert_includes Kb::RichProse.call(html), "<div>hello</div>"
    assert_includes Kb::RichProse.call(html), "<ul><li>x*y</li></ul>"
    assert_no_match(/<script|javascript:/, Kb::RichProse.call(%(<div class="trix-content"><p>*a*</p><p><a href="javascript:x">y</a></p></div>)))
  end
end
