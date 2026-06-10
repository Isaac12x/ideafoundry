require "test_helper"

class TypingTextLibraryTest < ActiveSupport::TestCase
  test "unlock prompt library has a broad set of distinct prompts" do
    texts = TypingTextLibrary::UNLOCK_TEXTS.values

    assert_operator texts.size, :>=, 33
    assert_equal texts.size, texts.uniq.size
  end

  test "unlock prompt library includes source inspired prompts" do
    assert_includes TypingTextLibrary::UNLOCK_TEXTS["ford-better-ways"], "new and better ways"
    assert_includes TypingTextLibrary::UNLOCK_TEXTS["feynman-question"], "leaves room for doubt"
    assert_includes TypingTextLibrary::UNLOCK_TEXTS["rines-conformity"], "enemy of innovation"
  end
end
