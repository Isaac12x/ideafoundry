require "test_helper"

class Kb::BookConversionTest < ActiveSupport::TestCase
  test "sidecar is a hidden dotfile beside the book, pdf for djvu" do
    assert_equal "/kb/.novel.mobi.epub", Kb::BookConversion.sidecar("/kb/novel.mobi")
    assert_equal "/kb/.scan.djvu.pdf", Kb::BookConversion.sidecar("/kb/scan.djvu")
  end

  test "missing tool gives an actionable message" do
    ENV["EBOOK_CONVERT_BIN"] = nil
    Kb::LocalTool.stub(:path, nil) do
      File.stub(:executable?, false) do
        assert_nil Kb::BookConversion.tool("/kb/a.mobi")
        assert_includes Kb::BookConversion.install_hint("/kb/a.mobi"), "brew install --cask calibre"
        assert_includes Kb::BookConversion.install_hint("/kb/a.djvu"), "brew install djvulibre"
        error = assert_raises(Kb::BookConversion::Error) { Kb::BookConversion.convert!("/kb/a.mobi") }
        assert_includes error.message, "calibre"
      end
    end
  end

  test "converts with the configured binary and treats a stale sidecar as not ready" do
    dir = Dir.mktmpdir("kb-book")
    fake = File.join(dir, "fake-convert")
    File.write(fake, "#!/bin/sh\necho epub > \"$2\"\n")
    File.chmod(0o755, fake)
    book = File.join(dir, "a.mobi")
    File.write(book, "x")
    ENV["EBOOK_CONVERT_BIN"] = fake

    assert_not Kb::BookConversion.ready?(book)
    Kb::BookConversion.convert!(book)
    assert Kb::BookConversion.ready?(book)
    File.utime(Time.now + 60, Time.now + 60, book)
    assert_not Kb::BookConversion.ready?(book)
  ensure
    ENV.delete("EBOOK_CONVERT_BIN")
    FileUtils.rm_rf(dir)
    FileUtils.rm_rf(Kb::BookConversion.state_dir)
  end
end
