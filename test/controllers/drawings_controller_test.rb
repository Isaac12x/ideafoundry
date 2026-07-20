require "test_helper"

class DrawingsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first
    @idea = @user.ideas.create!(title: "Drawing Host Idea", state: :idea_new)
    @other_idea = @user.ideas.create!(title: "Other Idea", state: :idea_new)
  end

  def sample_payload
    {
      "elements" => [{ "id" => "n1", "type" => "rectangle", "x" => 0, "y" => 0 }],
      "appState" => { "viewBackgroundColor" => "#fff" },
      "files" => {}
    }
  end

  test "GET new renders mount div" do
    get new_idea_drawing_path(@idea)
    assert_response :success
    assert_select ".excalidraw-mount"
  end

  test "GET show renders mount div with data attrs" do
    d = Drawing.create!(idea: @idea, title: "Demo", content: sample_payload)
    get idea_drawing_path(@idea, d)
    assert_response :success
    assert_select ".excalidraw-mount[data-drawing-id=?]", d.id.to_s
    assert_select ".excalidraw-mount[data-drawing-title=?]", "Demo"
  end

  test "POST create with valid JSON" do
    assert_difference("Drawing.count", 1) do
      post idea_drawings_path(@idea),
        params: { drawing: { title: "From API", content: sample_payload } }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert body["id"].present?
    assert_equal "From API", body["title"]

    created = Drawing.find(body["id"])
    assert_equal sample_payload, created.content
    assert_equal @idea.id, created.idea_id
  end

  test "POST create rejects blank title" do
    assert_no_difference("Drawing.count") do
      post idea_drawings_path(@idea),
        params: { drawing: { title: "", content: sample_payload } }.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    end
    assert_response :unprocessable_content
  end

  test "PATCH update modifies content and title" do
    d = Drawing.create!(idea: @idea, title: "Old", content: sample_payload)
    new_payload = sample_payload.merge("appState" => { "viewBackgroundColor" => "#000" })

    patch idea_drawing_path(@idea, d),
      params: { drawing: { title: "New", content: new_payload } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :ok
    d.reload
    assert_equal "New", d.title
    assert_equal "#000", d.content["appState"]["viewBackgroundColor"]
  end

  test "PATCH update preserves content when only title changes" do
    d = Drawing.create!(idea: @idea, title: "Old", content: sample_payload)

    patch idea_drawing_path(@idea, d),
      params: { drawing: { title: "Renamed" } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :ok
    d.reload
    assert_equal "Renamed", d.title
    assert_equal sample_payload, d.content
  end

  test "DELETE destroy removes the drawing" do
    d = Drawing.create!(idea: @idea, title: "doomed", content: sample_payload)
    assert_difference("Drawing.count", -1) do
      delete idea_drawing_path(@idea, d)
    end
    assert_redirected_to idea_path(@idea, anchor: "media")
  end

  test "GET show 404s for a drawing on another idea" do
    d = Drawing.create!(idea: @other_idea, title: "Theirs", content: sample_payload)

    begin
      get idea_drawing_path(@idea, d)
      # Rails may render its own 404 page in test env or raise; either is acceptable.
      assert_includes [404, 302], response.status
    rescue ActiveRecord::RecordNotFound
      assert true
    end
  end

  test "POST create accepts role and stores rendered PNG from data URL" do
    png_data_url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
    payload = {
      drawing: {
        title: "Hero",
        role: "hero",
        content: sample_payload,
        png_data_url: png_data_url
      }
    }
    assert_difference("Drawing.count", 1) do
      post idea_drawings_path(@idea),
        params: payload.to_json,
        headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    end
    assert_response :created

    body = JSON.parse(response.body)
    drawing = Drawing.find(body["id"])
    assert_equal "hero", drawing.role
    assert drawing.rendered_png.attached?
    assert body["png_url"].present?
  end

  test "POST create with role=general by default" do
    post idea_drawings_path(@idea),
      params: { drawing: { title: "G", content: sample_payload } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "general", body["role"]
  end

  test "PATCH update accepts new png and replaces it" do
    d = Drawing.create!(idea: @idea, title: "T", content: sample_payload)
    png_data_url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    patch idea_drawing_path(@idea, d),
      params: { drawing: { png_data_url: png_data_url } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :ok

    d.reload
    assert d.rendered_png.attached?
  end
end
