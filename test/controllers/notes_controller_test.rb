require "test_helper"

class NotesControllerTest < ActionDispatch::IntegrationTest
  test "tab partial renders day group and empty state" do
    idea = Idea.first
    skip "no idea fixture" unless idea
    idea.notes.destroy_all
    html = ApplicationController.render(partial: "notes/tab", locals: { idea: idea })
    assert_includes html, "notes-empty"
    idea.notes.create!(body: "hello **x**")
    html = ApplicationController.render(partial: "notes/tab", locals: { idea: idea })
    assert_includes html, "notes-day-label"
    assert_includes html, "Today"
    assert_includes html, "hello"
  end
end
