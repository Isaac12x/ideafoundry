require "test_helper"

class IdeaNapkinTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "napkin@test.example", name: "Napkin User")
    @idea = @user.ideas.create!(title: "T", state: :idea_new, attempt_count: 0)
  end

  test "napkin_present? false when nil" do
    assert_nil @idea.napkin_calculations
    assert_not @idea.napkin_present?
  end

  test "napkin_present? false when cells empty" do
    @idea.update!(napkin_calculations: { "rows" => 10, "cols" => 5, "cells" => {} })
    assert_not @idea.napkin_present?
  end

  test "napkin_present? true when cells populated" do
    @idea.update!(napkin_calculations: {
      "rows" => 10, "cols" => 5,
      "cells" => { "A1" => { "raw" => "Users", "fmt" => nil } }
    })
    assert @idea.napkin_present?
  end

  test "napkin_cell returns cell hash or nil" do
    @idea.update!(napkin_calculations: {
      "rows" => 10, "cols" => 5,
      "cells" => { "A1" => { "raw" => "1000", "fmt" => "number:0" } }
    })
    assert_equal({ "raw" => "1000", "fmt" => "number:0" }, @idea.napkin_cell("A1"))
    assert_nil @idea.napkin_cell("Z99")
  end

  test "rejects payload with too many cells" do
    cells = (1..2001).each_with_object({}) { |i, h| h["A#{i}"] = { "raw" => "x", "fmt" => nil } }
    @idea.napkin_calculations = { "rows" => 100, "cols" => 26, "cells" => cells }
    assert_not @idea.valid?
    assert_includes @idea.errors[:napkin_calculations].to_s, "too many cells"
  end

  test "rejects payload with rows > 100" do
    @idea.napkin_calculations = { "rows" => 101, "cols" => 5, "cells" => {} }
    assert_not @idea.valid?
    assert_includes @idea.errors[:napkin_calculations].to_s, "rows"
  end

  test "rejects payload with cols > 26" do
    @idea.napkin_calculations = { "rows" => 10, "cols" => 27, "cells" => {} }
    assert_not @idea.valid?
    assert_includes @idea.errors[:napkin_calculations].to_s, "cols"
  end

  test "JSON round-trip preserves structure" do
    payload = {
      "rows" => 10, "cols" => 5,
      "cells" => {
        "A1" => { "raw" => "Users", "fmt" => nil },
        "B1" => { "raw" => "1000", "fmt" => "number:0" },
        "B3" => { "raw" => "=B1*2", "fmt" => "currency:USD:0" }
      }
    }
    @idea.update!(napkin_calculations: payload)
    @idea.reload
    assert_equal payload, @idea.napkin_calculations
  end
end
