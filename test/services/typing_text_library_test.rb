require "test_helper"

class TypingTextLibraryTest < ActiveSupport::TestCase
  test "unlock prompt library has a broad set of distinct prompts" do
    texts = TypingTextLibrary::UNLOCK_TEXTS.values

    assert_operator texts.size, :>=, 24
    assert_equal texts.size, texts.uniq.size
  end
end
