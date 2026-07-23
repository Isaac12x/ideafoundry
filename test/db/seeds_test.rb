require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeding leaves boards lists and ideas empty" do
    assert_no_difference [
      -> { KanbanBoard.count },
      -> { List.count },
      -> { Idea.count },
      -> { IdeaList.count }
    ] do
      capture_io { load Rails.root.join("db/seeds.rb") }
    end

    assert User.exists?(email: "user@example.com")
  end
end
