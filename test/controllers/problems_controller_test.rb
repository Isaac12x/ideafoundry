require "test_helper"

class ProblemsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { @user = User.first || User.create!(email: "test@example.com", name: "Test") }

  test "create saves, enqueues lookup, never blocks" do
    title = "Slippery rails #{SecureRandom.hex(3)}"
    assert_enqueued_with(job: ProblemLookupJob) do
      assert_difference -> { @user.problems.count } do
        post problems_path, params: { problem: { title: title, need: "n" } }, as: :turbo_stream
      end
    end
    assert_response :success
    assert_includes response.body, title
  end

  test "blank title rejected, find re-queues" do
    assert_no_difference -> { Problem.count } do
      post problems_path, params: { problem: { title: "" } }, as: :turbo_stream
    end
    p = @user.problems.create!(title: "x #{SecureRandom.hex(3)}")
    assert_enqueued_with(job: ProblemLookupJob) { post find_problem_path(p), as: :turbo_stream }
  end
end
