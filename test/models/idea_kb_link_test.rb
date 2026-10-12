require "test_helper"

class IdeaKbLinkTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @idea = @user.ideas.first || @user.ideas.create!(title: "I", description: "d")
  end

  test "move_subtree! moves nested links and replaces conflicts" do
    @idea.kb_links.create!(source_path: "/kb", relative_path: "P", entry_type: "project")
    @idea.kb_links.create!(source_path: "/kb", relative_path: "P/a.md", entry_type: "file")
    @idea.kb_links.create!(source_path: "/kb", relative_path: "Pother", entry_type: "dir")
    @idea.kb_links.create!(source_path: "/kb", relative_path: "Q/a.md", entry_type: "file")

    IdeaKbLink.move_subtree!(user: @user, source_path: "/kb", old_relative_path: "P",
                             new_source_path: "/kb", new_relative_path: "Q")
    paths = @idea.kb_links.reload.pluck(:source_path, :relative_path)
    assert_includes paths, [ "/kb", "Q" ]
    assert_includes paths, [ "/kb", "Q/a.md" ]
    assert_includes paths, [ "/kb", "Pother" ]
    assert_equal 3, paths.size
  end

  test "for_path finds backlinks scoped to user and unique per idea" do
    @idea.kb_links.create!(source_path: "/kb", relative_path: "/P/", entry_type: "project")
    assert_equal 1, IdeaKbLink.for_path(user: @user, source_path: "/kb", relative_path: "P").count
    assert_not @idea.kb_links.build(source_path: "/kb", relative_path: "P", entry_type: "project").valid?
    assert_equal 0, IdeaKbLink.for_path(user: User.new(id: -1), source_path: "/kb", relative_path: "P").count
  end
end
