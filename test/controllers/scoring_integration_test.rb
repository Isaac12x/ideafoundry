require "test_helper"

class ScoringIntegrationTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @idea = ideas(:one)
  end

  test "should update idea scores via AJAX" do
    patch idea_path(@idea), 
          params: { 
            idea: { 
              trl: 8, 
              difficulty: 3, 
              opportunity: 9, 
              timing: 7 
            } 
          },
          headers: { 'X-Requested-With' => 'XMLHttpRequest' }
    
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert response_data['success']
    assert response_data['computed_score']
    
    @idea.reload
    assert_equal 8, @idea.trl
    assert_equal 3, @idea.difficulty
    assert_equal 9, @idea.opportunity
    assert_equal 7, @idea.timing
  end

  test "should update scoring weights via settings" do
    patch settings_scoring_path,
          params: {
            scoring_weights: {
              trl: 0.4,
              difficulty: -0.15,
              opportunity: 0.35,
              timing: 0.2
            }
          }
    
    assert_redirected_to settings_scoring_path
    follow_redirect!
    assert_match /updated successfully/, response.body
    
    @user.reload
    weights = @user.scoring_weights
    assert_equal 0.4, weights['trl']
    assert_equal -0.15, weights['difficulty']
    assert_equal 0.35, weights['opportunity']
    assert_equal 0.2, weights['timing']
  end

  test "should get scoring weights via JSON" do
    get settings_scoring_weights_path, 
        headers: { 'Accept' => 'application/json' }
    
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert response_data['weights']
    assert response_data['formula']
    
    weights = response_data['weights']
    assert_equal 0.3, weights['trl']
    assert_equal -0.1, weights['difficulty']
    assert_equal 0.4, weights['opportunity']
    assert_equal 0.2, weights['timing']
  end

  test "should reject invalid scoring weights" do
    patch settings_scoring_path,
          params: {
            scoring_weights: {
              trl: 1.5,  # Invalid: > 1
              difficulty: -2.0,  # Invalid: < -1
              opportunity: 0.4,
              timing: 0.2
            }
          }
    
    assert_response :unprocessable_entity
    assert_match /Invalid scoring weights/, response.body
  end

  test "should handle AJAX scoring weight updates" do
    patch settings_scoring_path,
          params: {
            scoring_weights: {
              trl: 0.35,
              difficulty: -0.05,
              opportunity: 0.45,
              timing: 0.15
            }
          },
          headers: { 'X-Requested-With' => 'XMLHttpRequest' }
    
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert response_data['success']
    assert response_data['weights']
    assert_equal 0.35, response_data['weights']['trl']
  end
end