require "test_helper"

class ReferenceControllerTest < ActionDispatch::IntegrationTest
  setup { @note = PatentReference.all.first }

  test "index lists clusters and searches" do
    get reference_index_path
    assert_response :success
    assert_select "a[href=?]", reference_path(@note.slug)

    get reference_index_path(q: @note.title)
    assert_response :success
    assert_match "result", response.body
  end

  test "show renders a note and 404s unknown slugs" do
    get reference_path(@note.slug)
    assert_response :success
    assert_match @note.title, response.body

    get reference_path("no-such-note")
    assert_response :not_found
  end

  test "palette quick search includes Reference group" do
    get global_search_path(q: @note.title, format: :json)
    labels = JSON.parse(response.body)["groups"].map { |g| g["label"] }
    assert_includes labels, "Reference"
  end
end
