require "test_helper"

class Kb::SourceTest < ActiveSupport::TestCase
  test "round-trips url and description, only for http(s) links" do
    Dir.mktmpdir do |dir|
      abs = File.join(dir, "v.mp4")
      File.write(abs, "x")
      Kb::Source.write!(abs, url: "javascript:alert(1)")
      assert_empty Kb::Source.read(abs)

      Kb::Source.write!(abs, url: "https://example.com/v?a=1", description: "  hello  ")
      assert_equal({ "url" => "https://example.com/v?a=1", "description" => "hello" }, Kb::Source.read(abs))
      assert_nil Kb::Source.safe_url("ftp://x")
      refute Kb::Note.eligible?(Kb::Source.sidecar(abs))
    end
  end

  test "linked_html escapes the text and links only http(s) urls" do
    html = Kb::Source.linked_html(%(<script>x</script> see https://a.com/p?q=1&r=2. javascript:alert(1) "https://b.com"))
    assert_includes html, "&lt;script&gt;"
    assert_includes html, %(<a href="https://a.com/p?q=1&amp;r=2" target="_blank" rel="noopener noreferrer">https://a.com/p?q=1&amp;r=2</a>.)
    assert_not_includes html, "<script>"
    assert_not_includes html, 'href="javascript'
  end

  test "fetch_description! writes the sidecar from yt-dlp, argv only, http(s) only" do
    Dir.mktmpdir do |dir|
      abs = File.join(dir, "v.mp4")
      File.write(abs, "x")
      seen = nil
      fake = ->(args, **) { seen = args; [ "A description\nline two\n", Struct.new(:success?).new(true) ] }

      KbDownloadJob.stub(:yt_dlp_bin, "yt-dlp") do
        KbDownloadJob.stub(:capture, fake) do
          assert_equal :no_url, Kb::Source.fetch_description!(abs, "file:///etc/passwd")
          assert_equal :ok, Kb::Source.fetch_description!(abs, "https://example.com/v")
        end
      end
      assert_includes seen, "--skip-download"
      assert_equal "https://example.com/v", seen.last
      assert_equal "A description\nline two", Kb::Source.read(abs)["description"]

      KbDownloadJob.stub(:yt_dlp_bin, nil) { assert_equal :missing_tool, Kb::Source.fetch_description!(abs, "https://example.com/v") }
    end
  end
end
