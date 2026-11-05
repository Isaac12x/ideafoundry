require "test_helper"

class KbBookmarkTest < ActiveSupport::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @attrs = { source_path: "/kb", relative_path: "books/a.pdf" }
  end

  teardown { @user.kb_bookmarks.delete_all }

  test "needs exactly one of page or a well-formed epub cfi" do
    assert @user.kb_bookmarks.build(@attrs.merge(label: "p", page: 3)).valid?
    assert @user.kb_bookmarks.build(@attrs.merge(label: "c", cfi: "epubcfi(/6/4!/4/2)", progress: 0.4)).valid?
    assert_not @user.kb_bookmarks.build(@attrs.merge(label: "none")).valid?
    assert_not @user.kb_bookmarks.build(@attrs.merge(label: "both", page: 1, cfi: "epubcfi(/6/4)")).valid?
    assert_not @user.kb_bookmarks.build(@attrs.merge(label: "bad", cfi: "javascript:1")).valid?
    assert_not @user.kb_bookmarks.build(@attrs.merge(label: "zero", page: 0)).valid?
  end

  test "label is squished, required and capped" do
    assert_equal "a b", @user.kb_bookmarks.create!(@attrs.merge(label: "  a \n b ", page: 1)).label
    assert_not @user.kb_bookmarks.build(@attrs.merge(label: " ", page: 1)).valid?
    assert_not @user.kb_bookmarks.build(@attrs.merge(label: "x" * 121, page: 1)).valid?
  end

  test "a file holds at most MAX_PER_FILE bookmarks" do
    rows = Array.new(KbBookmark::MAX_PER_FILE) { |i| @attrs.merge(user_id: @user.id, label: "p#{i}", page: i + 1, created_at: Time.current, updated_at: Time.current) }
    KbBookmark.insert_all(rows)
    assert_not @user.kb_bookmarks.build(@attrs.merge(label: "one more", page: 999)).valid?
    assert @user.kb_bookmarks.build(@attrs.merge(relative_path: "other.pdf", label: "ok", page: 1)).valid?
  end

  test "bookmarks follow a moved folder and go with a deleted one" do
    @user.kb_bookmarks.create!(@attrs.merge(label: "p", page: 1))
    KbBookmark.move_subtree!(user: @user, source_path: "/kb", old_relative_path: "books", new_source_path: "/kb", new_relative_path: "shelf")
    assert_equal [ "shelf/a.pdf" ], @user.kb_bookmarks.where(source_path: "/kb").pluck(:relative_path)
    KbBookmark.delete_subtree!(user: @user, source_path: "/kb", relative_path: "shelf")
    assert_equal 0, @user.kb_bookmarks.where(source_path: "/kb").count
  end
end
