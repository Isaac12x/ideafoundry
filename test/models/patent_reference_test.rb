require "test_helper"

# Validates the shipped Patent Notes (content QA gate) and the lookup/search helpers.
class PatentReferenceTest < ActiveSupport::TestCase
  setup { PatentReference.reload! }

  test "every note is well-formed" do
    notes = PatentReference.all
    assert notes.any?, "no Patent Notes found"
    slugs = notes.map(&:slug)
    files = Dir.glob(PatentReference::ROOT.join("*/*.md"))
    assert_equal files.size, slugs.uniq.size, "duplicate slugs"

    notes.each do |n|
      path = files.find { |f| File.basename(f, ".md") == n.slug }
      assert path, "#{n.slug}: file name must equal slug"
      assert_equal n.cluster, File.basename(File.dirname(path)), "#{n.slug}: cluster must match folder"
      assert_includes PatentReference::CLUSTERS.keys, n.cluster, "#{n.slug}: unknown cluster"
      assert n.sources.any?, "#{n.slug}: sources missing"
      assert_includes n.body, "_Educational, not legal advice._", "#{n.slug}: disclaimer missing"
      assert_no_match(/\$\s?\d/, n.body, "#{n.slug}: no dollar amounts (link the USPTO fee schedule)")
      (n.related - slugs).each { |s| flunk "#{n.slug}: related slug #{s} does not exist" }
    end
  end

  test "find and search" do
    note = PatentReference.all.first
    assert_equal note, PatentReference.find(note.slug)
    assert_nil PatentReference.find("nope")
    assert_equal note.slug, PatentReference.search(note.title).first.slug
    assert_empty PatentReference.search("the and")
  end

  test "context_for only fires on patent topics" do
    assert_nil PatentReference.context_for("what should I cook tonight")
    assert_match "[[note:", PatentReference.context_for("how do dependent claims work in a patent").to_s
  end
end
