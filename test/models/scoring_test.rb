require "test_helper"

class ScoringTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @idea = Idea.create!(
      user: @user,
      title: "Test Scoring Idea",
      trl: 7,
      difficulty: 4,
      opportunity: 8,
      timing: 6
    )
  end

  test "should calculate score with default weights" do
    expected_score = (7 * 0.3 + 8 * 0.4 + 6 * 0.2 - 4 * 0.1).round(2)
    assert_equal expected_score, @idea.computed_score
  end

  test "should recalculate score when scoring attributes change" do
    @idea.update!(trl: 9, opportunity: 10)
    expected_score = (9 * 0.3 + 10 * 0.4 + 6 * 0.2 - 4 * 0.1).round(2)
    assert_equal expected_score, @idea.computed_score
  end

  test "should track scoring history in versions" do
    # Create initial version
    version1 = @idea.create_version("Initial scoring")
    
    # Update scores
    @idea.update!(trl: 9, difficulty: 2)
    version2 = @idea.create_version("Updated scoring")
    
    # Check scoring history
    history = @idea.scoring_history(limit: 2)
    assert_equal 2, history.length
    
    # Most recent should be first
    assert_equal version2.computed_score, history.first[:score]
    assert_equal version1.computed_score, history.second[:score]
  end

  test "should detect score trend" do
    # Create versions with improving scores
    @idea.update!(trl: 5, opportunity: 5)
    @idea.create_version("Lower score")
    
    @idea.update!(trl: 7, opportunity: 7)
    @idea.create_version("Medium score")
    
    @idea.update!(trl: 9, opportunity: 9)
    @idea.create_version("Higher score")
    
    assert_equal 'improving', @idea.score_trend
  end

  test "should calculate score change since last version" do
    # Create initial version
    initial_score = @idea.computed_score
    @idea.create_version("Initial version")
    
    # Update and create new version
    @idea.update!(trl: 9, opportunity: 10)
    new_score = @idea.computed_score
    @idea.create_version("Updated version")
    
    expected_change = new_score - initial_score
    assert_equal expected_change, @idea.score_change_since_last_version
  end

  test "version should track scoring changes" do
    # Create initial version
    version1 = @idea.create_version("Initial version")
    
    # Update scoring
    @idea.update!(trl: 9, difficulty: 2, opportunity: 10)
    version2 = @idea.create_version("Updated scoring")
    
    # Check scoring changes
    changes = version2.scoring_changes
    assert changes.key?('trl')
    assert changes.key?('difficulty')
    assert changes.key?('opportunity')
    assert changes.key?('computed_score')
    
    assert_equal 7, changes['trl'][:from]
    assert_equal 9, changes['trl'][:to]
    assert_equal 2, changes['trl'][:change]
  end

  test "should update user scoring weights" do
    new_weights = {
      'trl' => 0.4,
      'difficulty' => -0.2,
      'opportunity' => 0.3,
      'timing' => 0.1
    }
    
    @user.update_scoring_weights(new_weights)
    assert_equal new_weights, @user.scoring_weights
  end

  test "should recalculate score with new weights" do
    # Update weights
    new_weights = {
      'trl' => 0.4,
      'difficulty' => -0.2,
      'opportunity' => 0.3,
      'timing' => 0.1
    }
    @user.update_scoring_weights(new_weights)
    
    # Force recalculation
    @idea.send(:calculate_score)
    @idea.save!
    
    expected_score = (7 * 0.4 + 8 * 0.3 + 6 * 0.1 - 4 * 0.2).round(2)
    assert_equal expected_score, @idea.computed_score
  end
end