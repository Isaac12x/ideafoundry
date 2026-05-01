require "test_helper"

class IdeasControllerNapkinTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "napkin-ctl@test.example", name: "Napkin Ctl")
    @idea = @user.ideas.create!(title: "T", state: :idea_new, attempt_count: 0)
  end

  test "update accepts napkin_calculations JSON string and persists hash" do
    payload = {
      rows: 10, cols: 5,
      cells: {
        "A1" => { raw: "Users", fmt: nil },
        "B1" => { raw: "1000", fmt: "number:0" }
      }
    }
    patch idea_path(@idea), params: {
      idea: { title: "T2", state: "idea_new", napkin_calculations: payload.to_json }
    }
    assert_response :redirect
    @idea.reload
    assert_equal 10, @idea.napkin_calculations["rows"]
    assert_equal "Users", @idea.napkin_calculations["cells"]["A1"]["raw"]
  end

  test "update with blank napkin_calculations stores nil" do
    @idea.update!(napkin_calculations: { "rows" => 10, "cols" => 5, "cells" => { "A1" => { "raw" => "x", "fmt" => nil } } })
    patch idea_path(@idea), params: {
      idea: { title: "T", state: "idea_new", napkin_calculations: "" }
    }
    @idea.reload
    assert_nil @idea.napkin_calculations
  end

  test "update with invalid JSON ignores the param (does not crash)" do
    patch idea_path(@idea), params: {
      idea: { title: "T3", state: "idea_new", napkin_calculations: "not json{" }
    }
    @idea.reload
    assert_nil @idea.napkin_calculations
    assert_equal "T3", @idea.title
  end

  test "update without napkin_calculations key preserves existing value" do
    existing = { "rows" => 10, "cols" => 5, "cells" => { "A1" => { "raw" => "keep", "fmt" => nil } } }
    @idea.update!(napkin_calculations: existing)
    patch idea_path(@idea), params: {
      idea: { title: "T4", state: "idea_new" }
    }
    @idea.reload
    assert_equal existing, @idea.napkin_calculations
    assert_equal "T4", @idea.title
  end
end
