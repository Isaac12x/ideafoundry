require "test_helper"

class TopologyTest < ActiveSupport::TestCase
  test "software topology exposes a built in github url default field" do
    topology = Topology.new(user: users(:one), name: "Software", topology_type: :custom)

    field = topology.effective_default_field_definitions.find { |definition| definition["name"] == "github_url" }

    assert_equal "GitHub URL", field["label"]
    assert_equal "url", field["type"]
    assert_equal "github_url", field["instance_id"]
  end

  test "default field definitions are sanitized before storage" do
    topology = Topology.create!(
      user: users(:one),
      name: "Hardware",
      topology_type: :custom,
      default_field_definitions: [
        {
          "name" => "repository",
          "label" => "Repository",
          "type" => "url",
          "required" => "1",
          "placeholder" => "https://github.com/acme/project",
          "hacker" => "bad"
        }
      ]
    )

    field = topology.reload.default_field_definitions.first

    assert_equal "repository", field["name"]
    assert_equal "Repository", field["label"]
    assert_equal "url", field["type"]
    assert_equal true, field["required"]
    assert_equal "repository", field["instance_id"]
    assert_nil field["hacker"]
  ensure
    topology&.destroy
  end
end
