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

  test "folder context skips private projects and refuses them directly" do
    FileUtils.mkdir_p(File.join(@dir, "research", "proj"))
    File.write(File.join(@dir, "research", "proj", ".kb-project.yml"), "private: true\n")
    File.write(File.join(@dir, "research", "proj", "secret.md"), "TOP SECRET")

    context = Kb::ContextReader.new(base: @dir, relative_path: "research", kind: "folder").call
    assert_includes context, "# Evidence"
    refute_includes context, "TOP SECRET"
    refute_includes context, "proj"

    assert_raises(ArgumentError) do
      Kb::ContextReader.new(base: @dir, relative_path: "research/proj/secret.md", kind: "file").call
    end
  end

  test "rejects paths outside the source" do
    assert_raises(ArgumentError) do
      Kb::ContextReader.new(base: @dir, relative_path: "../outside", kind: "folder").call
    end
  end
end
