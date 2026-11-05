require "test_helper"
require "zip"
require "rubygems/package"

class Kb::ArchiveTest < ActiveSupport::TestCase
  setup { @dir = Dir.mktmpdir("kb-archive") }
  teardown { FileUtils.rm_rf(@dir) }

  def zip_with(name, files)
    path = File.join(@dir, name)
    Zip::OutputStream.open(path) do |zip|
      files.each { |entry, data| zip.put_next_entry(entry); zip.write(data) }
    end
    path
  end

  def tar_with(name, files, gzip: false)
    path = File.join(@dir, name)
    File.open(path, "wb") do |file|
      io = gzip ? Zlib::GzipWriter.new(file) : file
      Gem::Package::TarWriter.new(io) { |tar| files.each { |entry, data| tar.add_file_simple(entry, 0o644, data.bytesize) { |f| f.write(data) } } }
      io.close if gzip
    end
    path
  end

  test "lists zip entries and drops unsafe names" do
    path = zip_with("a.zip", "docs/readme.txt" => "hello", "../evil.txt" => "x", "b.txt" => "12")
    listing = Kb::Archive.list(path)
    assert_equal %w[b.txt docs/readme.txt], listing.entries.map(&:path).sort
    assert_equal 7, listing.total_size
  end

  test "reads one entry by exact listed name only" do
    path = zip_with("a.zip", "docs/readme.txt" => "hello")
    assert_equal "hello", Kb::Archive.read_entry(path, "docs/readme.txt")
    assert_raises(Kb::Archive::NotFound) { Kb::Archive.read_entry(path, "../docs/readme.txt") }
    assert_raises(Kb::Archive::NotFound) { Kb::Archive.read_entry(path, "docs/*") }
  end

  test "entry size cap" do
    path = zip_with("a.zip", "big.txt" => "x" * 100)
    assert_raises(Kb::Archive::TooLarge) { Kb::Archive.read_entry(path, "big.txt", cap: 10) }
  end

  test "tar and tar.gz" do
    [ tar_with("a.tar", { "d/x.txt" => "tar!" }), tar_with("a.tar.gz", { "d/x.txt" => "tar!" }, gzip: true) ].each do |path|
      assert_equal [ "d/x.txt" ], Kb::Archive.list(path).files.map(&:path)
      assert_equal "tar!", Kb::Archive.read_entry(path, "d/x.txt")
    end
  end

  test "7z through the local tool, and a clear error when it is missing" do
    skip "7z not installed" unless Kb::Archive.seven_zip
    src = File.join(@dir, "src"); FileUtils.mkdir_p(File.join(src, "sub"))
    File.write(File.join(src, "sub", "n 1.txt"), "seven")
    out = File.join(@dir, "a.7z")
    system(Kb::Archive.seven_zip, "a", out, "#{src}/.", out: File::NULL)
    assert_equal "seven", Kb::Archive.read_entry(out, "sub/n 1.txt")
    assert Kb::Archive.list(out).entries.find { |e| e.path == "sub" }.dir

    Kb::Archive.stub(:seven_zip, nil) { assert_raises(Kb::Archive::MissingTool) { Kb::Archive.list(out) } }
  end

  test "corrupt archive is a readable error" do
    path = File.join(@dir, "bad.zip"); File.write(path, "not a zip")
    assert_raises(Kb::Archive::Error) { Kb::Archive.list(path) }
  end

  test "comic pages are images in natural order" do
    path = zip_with("c.cbz", "p10.jpg" => "a", "p2.jpg" => "b", "p1.png" => "c", "notes.txt" => "d", "__MACOSX/p1.png" => "e", "x.svg" => "<svg/>")
    assert_equal %w[p1.png p2.jpg p10.jpg], Kb::Archive.pages(Kb::Archive.list(path)).map(&:path)
  end

  test "tree nests folders first" do
    entries = [ Kb::Archive::Entry.new(path: "b.txt", size: 1, dir: false), Kb::Archive::Entry.new(path: "z/a.txt", size: 1, dir: false) ]
    tree = Kb::Archive.tree(entries)
    assert_equal %w[z b.txt], tree.keys
    assert_equal %w[a.txt], tree["z"][:children].keys
  end
end
