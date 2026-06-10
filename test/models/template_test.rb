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

  test "stores one or more scoring systems" do
    template = Template.create!(
      user: users(:one),
      name: "Scoreable Template #{SecureRandom.hex(4)}",
      field_definitions: [],
      section_order: [],
      tab_definitions: [{ "name" => "general", "label" => "General", "position" => 0 }],
      scoring_system_ids: [User::LEGACY_SCORING_SYSTEM_ID, User::FOUNDER_SCORECARD_SYSTEM_ID]
    )

    assert_equal [User::LEGACY_SCORING_SYSTEM_ID, User::FOUNDER_SCORECARD_SYSTEM_ID], template.enabled_scoring_system_ids
    assert_equal ["Weighted readiness", "Founder scorecard"], template.scoring_systems.map { |system| system["name"] }
  end
end
