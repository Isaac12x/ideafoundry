require "test_helper"

class KbContextReaderTest < ActiveSupport::TestCase
  setup do
    @dir = Rails.root.join("tmp", "kb-context-reader-#{SecureRandom.hex(6)}").to_s
    FileUtils.mkdir_p(File.join(@dir, "research"))
    File.write(File.join(@dir, "research", "note.md"), "# Evidence")
    File.binwrite(File.join(@dir, "research", "image.bin"), "opaque")
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "folder context lists files and includes readable text" do
    context = Kb::ContextReader.new(base: @dir, relative_path: "research", kind: "folder").call

    assert_includes context, "note.md"
    assert_includes context, "image.bin"
    assert_includes context, "# Evidence"
    refute_includes context, "opaque"
  end

  test "rejects paths outside the source" do
    assert_raises(ArgumentError) do
      Kb::ContextReader.new(base: @dir, relative_path: "../outside", kind: "folder").call
    end
  end
end
