require "test_helper"

class Kb::TreeBuilderTest < ActiveSupport::TestCase
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)

    @user = users(:one)
    @root = Rails.root.join("tmp/kb_tree_builder_test_#{Process.pid}_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root)
    File.write(@root.join("note.md"), "# Hello")

    @source = { path: @root.to_s, label: "Test", native: false, drive: false }
    KbSource.stub(:list, [@source]) do
      @builder = Kb::TreeBuilder.new(@user)
    end
    Rails.cache.clear
    Kb::TreeBuilder.bust_cache!(@user)
  end

  teardown do
    FileUtils.rm_rf(@root) if @root&.exist?
    Rails.cache = @previous_cache if defined?(@previous_cache)
  end

  test "filesystem scan is cached until bust_cache!" do
    scans = 0
    scan = ->(base) {
      scans += 1
      { files: [{ rel: "note.md", abs: File.join(base, "note.md") }], dirs: [] }
    }

    KbSource.stub(:list, [@source]) do
      @builder.stub(:scan_filesystem_entries, scan) do
        2.times { @builder.call }
        assert_equal 1, scans, "expected one filesystem scan for repeated builds"

        Kb::TreeBuilder.bust_cache!(@user)
        @builder.call
        assert_equal 2, scans, "expected a fresh scan after bust_cache!"
      end
    end
  end
end
