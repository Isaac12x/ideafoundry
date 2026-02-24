require "test_helper"

class ClustersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @idea = ideas(:one)
    # Ensure this user is the first user since controller uses User.first
    User.where.not(id: @user.id).destroy_all
  end

  test "should get index" do
    get clusters_url
    assert_response :success
    assert_select "h2", "Cluster View"
  end

  test "should update idea position" do
    patch update_idea_position_clusters_url(format: :json), 
          params: { idea_id: @idea.id, x: 100.5, y: 200.5 }.to_json,
          headers: { 'Content-Type': 'application/json' }
    
    assert_response :success
    @idea.reload
    assert_equal 100.5, @idea.cluster_x
    assert_equal 200.5, @idea.cluster_y
  end

  test "should create cluster" do
    initial_clusters_count = @user.settings&.dig('clusters')&.size || 0
    
    post create_cluster_clusters_url(format: :json),
         params: { 
           name: "Test Cluster", 
           x: 50, 
           y: 50, 
           width: 200, 
           height: 150 
         }.to_json,
         headers: { 'Content-Type': 'application/json' }
    
    assert_response :success
    @user.reload
    clusters = @user.settings['clusters']
    assert_not_nil clusters
    assert_equal initial_clusters_count + 1, clusters.size
    
    cluster = clusters.values.last
    assert_equal "Test Cluster", cluster['name']
    assert_equal 50, cluster['x']
    assert_equal 50, cluster['y']
    assert_equal 200, cluster['width']
    assert_equal 150, cluster['height']
  end

  test "should destroy cluster" do
    # First create a cluster
    clusters = { 
      "test-id" => {
        "name" => "Test Cluster",
        "x" => 50,
        "y" => 50,
        "width" => 200,
        "height" => 150
      }
    }
    settings = @user.settings || {}
    settings["clusters"] = clusters
    @user.update(settings: settings)

    delete destroy_cluster_clusters_url("test-id", format: :json)
    assert_response :success
    
    @user.reload
    updated_settings = @user.settings || {}
    assert_empty updated_settings.dig('clusters') || {}
  end

  test "should handle invalid idea id gracefully" do
    patch update_idea_position_clusters_url(format: :json),
          params: { idea_id: 99999, x: 100, y: 200 }.to_json,
          headers: { 'Content-Type': 'application/json' }
    
    assert_response :not_found
  end
end