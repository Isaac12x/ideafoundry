require "test_helper"

class Kb::NoteTest < ActiveSupport::TestCase
  setup do
    @root = Rails.root.join("tmp/kb_note_test_#{Process.pid}_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root)
    @media = @root.join("clip.mp4").to_s
    File.binwrite(@media, "x")
  end

  teardown { FileUtils.rm_rf(@root) }

  test "sidecar is <filename>.note.md and only non-markdown files are eligible" do
    assert_equal "#{@media}.note.md", Kb::Note.sidecar(@media)
    assert Kb::Note.eligible?(@media)
    assert Kb::Note.eligible?("a.pdf")
    refute Kb::Note.eligible?("a.md")
    refute Kb::Note.eligible?("a.mp4.note.md")
  end

  test "write, read, blank removes" do
    assert_equal "", Kb::Note.read(@media)
    assert_nil Kb::Note.sidecar_for(@media)

    Kb::Note.write!(@media, "  because the intro is the pattern  ")
    assert_equal "because the intro is the pattern\n", Kb::Note.read(@media)
    assert_equal Kb::Note.sidecar(@media), Kb::Note.sidecar_for(@media)

    Kb::Note.write!(@media, "  ")
    refute File.exist?(Kb::Note.sidecar(@media))
  end

  test "oversized note is refused" do
    assert_raises(ArgumentError) { Kb::Note.write!(@media, "a" * (Kb::Note::MAX_BYTES + 1)) }
  end

  test "tree hides the note sidecar and marks its file; orphan notes stay visible" do
    Kb::Note.write!(@media, "why")
    File.write(@root.join("orphan.mp4.note.md"), "alone")
    File.binwrite(@root.join("doc.pdf"), "x")
    Kb::Note.write!(@root.join("doc.pdf").to_s, "also why")

    user = users(:one)
    builder = KbSource.stub(:list, [ { path: @root.to_s, label: "T", native: false, drive: false } ]) { Kb::TreeBuilder.new(user) }
    files = builder.send(:scan_filesystem_entries, @root.to_s)[:files]
    rels = files.map { |f| f[:rel] }

    refute_includes rels, "clip.mp4.note.md"
    refute_includes rels, "doc.pdf.note.md"
    assert_includes rels, "orphan.mp4.note.md"
    assert_equal "why", files.find { |f| f[:rel] == "clip.mp4" }[:note]
    assert files.find { |f| f[:rel] == "doc.pdf" }[:note]
  end

  test "preview is the first non-blank line, truncated" do
    Kb::Note.write!(@media, "\n\n#{'a' * 200}\nsecond")
    assert_equal 120, Kb::Note.preview(@media).length
    assert_nil Kb::Note.preview(@root.join("none.mp4").to_s)
    Kb::Note.write!(@media, "## Saved for the **print** plan -> v2")
    assert_equal "Saved for the print plan → v2", Kb::Note.preview(@media)
  end
end
