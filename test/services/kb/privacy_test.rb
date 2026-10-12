require "test_helper"

class Kb::PrivacyTest < ActiveSupport::TestCase
  setup do
    @base = Dir.mktmpdir
    Kb::Project.create!(base: @base, parent_rel: "", name: "Secret")
    Kb::Project.create!(base: @base, parent_rel: "", name: "Open", private: false)
    FileUtils.mkdir_p(File.join(@base, "Secret/sub"))
    FileUtils.mkdir_p(File.join(@base, "plain"))
  end
  teardown { FileUtils.rm_rf(@base) }

  test "private inside or at private project only" do
    assert Kb::Privacy.private?(@base, "Secret")
    assert Kb::Privacy.private?(@base, "Secret/sub/a.md")
    assert_not Kb::Privacy.private?(@base, "Open/a.md")
    assert_not Kb::Privacy.private?(@base, "plain/a.md")
    assert_not Kb::Privacy.private?(@base, "")
  end

  test "traversal fails closed and memo works" do
    assert Kb::Privacy.private?(@base, "plain/../../x")
    memo = {}
    assert Kb::Privacy.private?(@base, "Secret/sub", memo)
    assert_equal true, memo["#{File.expand_path(@base)}\0Secret"]
  end

  test "tree builder annotates projects and private nodes" do
    tree = {
      "Secret" => { type: :dir, rel: "Secret", children: { "a.md" => { type: :file, rel: "Secret/a.md" } } },
      "Open" => { type: :dir, rel: "Open", children: {} },
      "plain" => { type: :dir, rel: "plain", children: {} }
    }
    Kb::TreeBuilder.new(nil).send(:annotate_projects, tree, @base)
    assert_equal "active", tree["Secret"][:project][:status]
    assert tree["Secret"][:private]
    assert tree["Secret"][:children]["a.md"][:private]
    assert_equal false, tree["Open"][:project][:private]
    assert_nil tree["Open"][:private]
    assert_nil tree["plain"][:project]
  end
end
