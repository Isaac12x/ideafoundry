require "test_helper"

class TemplateTest < ActiveSupport::TestCase
  test "allows url fields in templates" do
    template = Template.new(
      user: users(:one),
      name: "Software Project",
      field_definitions: [
        {
          "name" => "github_url",
          "label" => "GitHub URL",
          "type" => "url",
          "instance_id" => "github_url",
          "required" => false
        }
      ],
      section_order: [],
      tab_definitions: [{ "name" => "general", "label" => "General", "position" => 0 }]
    )

    assert template.valid?, template.errors.full_messages.to_sentence
  end
end
