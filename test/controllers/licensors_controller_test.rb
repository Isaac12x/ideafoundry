require "test_helper"

class LicensorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "lc-test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Licensable Idea", for_licensing: true)
  end

  test "create adds a licensor and returns the tab turbo stream" do
    assert_difference("Licensor.count", 1) do
      post idea_licensors_path(@idea, format: :turbo_stream),
           params: { licensor: { company: "Acme", stage: "identified" } }
    end
    assert_response :success
    assert_match "licensors_tab_#{@idea.id}", response.body
    assert_match "Acme", response.body
  end

  test "create with blank company reports errors without persisting" do
    assert_no_difference("Licensor.count") do
      post idea_licensors_path(@idea, format: :turbo_stream), params: { licensor: { company: "" } }
    end
    assert_response :unprocessable_content
  end

  test "update stage from the board re-renders the board" do
    licensor = @idea.licensors.create!(company: "Acme")
    patch licensor_path(licensor, format: :turbo_stream),
          params: { context: "board", licensor: { stage: "contacted", position: 1 } }
    assert_response :success
    assert_equal "contacted", licensor.reload.stage
    assert_match "crm-board", response.body
  end

  test "update stage from the tab re-renders the tab" do
    licensor = @idea.licensors.create!(company: "Acme")
    patch licensor_path(licensor, format: :turbo_stream),
          params: { context: "tab", licensor: { stage: "meeting" } }
    assert_response :success
    assert_equal "meeting", licensor.reload.stage
    assert_match "licensors_tab_#{@idea.id}", response.body
  end

  test "show renders the record panel" do
    licensor = @idea.licensors.create!(company: "Acme")
    get licensor_path(licensor)
    assert_response :success
    assert_match "licensor-panel", response.body
    assert_match "Contact log", response.body
  end

  test "destroy removes the licensor" do
    licensor = @idea.licensors.create!(company: "Acme")
    assert_difference("Licensor.count", -1) do
      delete licensor_path(licensor, format: :turbo_stream), params: { context: "tab" }
    end
    assert_response :success
  end

  test "flagged idea shows the Potential Licensors tab and hides Tools/Notes" do
    @user.update_idea_tab_settings({ "tool" => "1", "notes" => "1" })
    @idea.licensors.create!(company: "Acme")

    get idea_path(@idea)
    assert_response :success
    assert_match "Potential Licensors", response.body
    assert_match "licensors_tab_#{@idea.id}", response.body
    assert_no_match(/data-tab-name="tool"/, response.body)
    assert_no_match(/data-tab-name="notes"/, response.body)
  end

  test "a licensor belonging to another user is not reachable" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", name: "Other")
    other_idea = other.ideas.create!(title: "Theirs", for_licensing: true)
    other_licensor = other_idea.licensors.create!(company: "Secret Co")

    # set_user resolves to User.first (our @user); the scoped lookup must miss.
    skip "single-user app: User.first is the other user" if User.first == other

    get licensor_path(other_licensor)
    assert_response :not_found
  end
end
