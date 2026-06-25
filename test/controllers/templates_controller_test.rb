require "test_helper"

class TemplatesControllerTest < ActionDispatch::IntegrationTest
  # The app is single-user: the current user is always User.first. Scope the
  # template under test to that user so set_template can find it.
  setup do
    @user = User.first
    @template = @user.templates.create!(
      name: "Test Template",
      field_definitions: [],
      section_order: [],
      scoring_system_ids: [User::LEGACY_SCORING_SYSTEM_ID]
    )
  end

  test "should get index" do
    get templates_url
    assert_response :success
  end

  test "should get new" do
    get new_template_url
    assert_response :success
  end

  test "should create template" do
    assert_difference("Template.count", 1) do
      post templates_url, params: { template: {
        name: "Brand New Template",
        field_definitions: { "0" => { name: "field_a", label: "Field A", type: "text" } },
        section_order: { "0" => "header", "1" => "description" }
      } }
    end
    assert_redirected_to settings_templates_path
  end

  test "should show template" do
    get template_url(@template, format: :json)
    assert_response :success
  end

  test "should get edit" do
    get edit_template_url(@template)
    assert_response :success
  end

  test "should update template" do
    patch template_url(@template), params: { template: { name: "Updated Template" } }
    assert_redirected_to template_url(@template)
    assert_equal "Updated Template", @template.reload.name
  end

  test "should destroy template" do
    assert_difference("Template.count", -1) do
      delete template_url(@template)
    end
    assert_redirected_to templates_path
  end
end
