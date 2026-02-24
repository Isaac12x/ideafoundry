require "test_helper"

class TopologiesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: 'test@example.com', name: 'Test')
    @topology = @user.topologies.create!(name: "Test Topo #{SecureRandom.hex(4)}", topology_type: :custom, color: '#ff0000')
  end

  test "graph_data includes settings in JSON" do
    get graph_data_topologies_path(format: :json)
    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?('settings'), "Response should include settings"
    assert_equal 'td', json['settings']['default_dag_mode']
    assert_equal true, json['settings']['show_ideas']
  end

  test "graph_data includes custom settings" do
    @user.update_topology_settings({ 'show_ideas' => false, 'bloom_strength' => 0.3 })
    get graph_data_topologies_path(format: :json)
    json = JSON.parse(response.body)
    assert_equal false, json['settings']['show_ideas']
    assert_equal 0.3, json['settings']['bloom_strength']
  end

  test "neighborhood includes settings with per-topology overrides" do
    @user.update_topology_overrides(@topology.id, { 'show_ideas' => false, 'dag_mode' => '' })
    get neighborhood_topology_path(@topology, format: :json)
    json = JSON.parse(response.body)
    assert json.key?('settings')
    assert_equal false, json['settings']['show_ideas']
  end

  teardown do
    @topology&.destroy
  end
end
