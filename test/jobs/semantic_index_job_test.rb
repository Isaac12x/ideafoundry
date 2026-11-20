require "test_helper"

class SemanticIndexJobTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Zebrafish tracker")
    @calls = []
  end

  def run_job(*args)
    SemanticSearch.stub(:enabled?, true) do
      SemanticSearch.stub(:upsert, ->(items) { @calls << [ :upsert, items.map { |i| i[:id] } ]; {} }) do
        SemanticSearch.stub(:delete, ->(ids) { @calls << [ :delete, ids ]; {} }) do
          SemanticSearch.stub(:prune, ->(prefix, keep) { @calls << [ :prune, prefix, keep ]; {} }) do
            SemanticIndexJob.perform_now(*args)
          end
        end
      end
    end
  end

  test "single idea is upserted, or deleted once discarded" do
    run_job(@user.id, @idea.id)
    assert_equal [ [ :upsert, [ SemanticSearch.idea_id(@user.id, @idea.id) ] ] ], @calls
    @calls.clear
    @idea.update_columns(discarded_at: Time.current)
    run_job(@user.id, @idea.id)
    assert_equal [ [ :delete, [ SemanticSearch.idea_id(@user.id, @idea.id) ] ] ], @calls
  end

  test "full sweep upserts then prunes keeping every sent id" do
    run_job(@user.id)
    id = SemanticSearch.idea_id(@user.id, @idea.id)
    assert_includes @calls.first.last, id
    assert_equal [ :prune, "u#{@user.id}:" ], @calls.last.first(2)
    assert_includes @calls.last.last, id
  end
end
