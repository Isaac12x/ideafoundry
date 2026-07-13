require "test_helper"

class KbEntryPreferenceTest < ActiveSupport::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
  end

  test "root favourites allow an empty relative path" do
    preference = @user.kb_entry_preferences.create!(
      source_path: "/tmp/example-kb",
      relative_path: "",
      entry_type: "root",
      favorite: true
    )

    assert preference.favorite?
  end

  test "moving a subtree rewrites every descendant preference" do
    folder = @user.kb_entry_preferences.create!(
      source_path: "/tmp/example-kb",
      relative_path: "research",
      entry_type: "folder",
      emoji: "🔬",
      icon_kind: "emoji"
    )
    file = @user.kb_entry_preferences.create!(
      source_path: "/tmp/example-kb",
      relative_path: "research/note.md",
      entry_type: "file",
      favorite: true
    )

    KbEntryPreference.move_subtree!(
      user: @user,
      source_path: "/tmp/example-kb",
      old_relative_path: "research",
      new_source_path: "/tmp/other-kb",
      new_relative_path: "sources"
    )

    assert_equal ["/tmp/other-kb", "sources"], [folder.reload.source_path, folder.relative_path]
    assert_equal ["/tmp/other-kb", "sources/note.md"], [file.reload.source_path, file.relative_path]
  end
end
