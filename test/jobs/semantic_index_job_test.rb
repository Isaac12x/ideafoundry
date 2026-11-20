require "test_helper"

class SemanticIndexJobTest < ActiveJob::TestCase
  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "a.md"), "alpha\n\nbeta")
    File.write(File.join(@dir, "b.txt"), "gamma")
    @enq = []
    @del = []
  end

  teardown { FileUtils.remove_entry(@dir) }

  def run_job(*args, health: nil)
    SemanticSearch.stub(:health, health) do
      run_job_inner(*args)
    end
  end

  def run_job_inner(*args)
    SemanticSearch.stub(:enabled?, true) do
      SemanticSearch.stub(:enqueue, ->(items) { @enq << items; { "queued" => items.size } }) do
        SemanticSearch.stub(:delete, ->(ids) { @del << ids; {} }) do
          KbSource.stub(:list, [ { path: @dir, label: "t" } ]) { SemanticIndexJob.perform_now(@user.id, *args) }
        end
      end
    end
  end

  def sent = @enq.flatten.map { |i| i[:id].split(":").last }.sort

  test "first delta sends everything with sections, second sends nothing" do
    run_job
    assert_equal %w[a.md b.txt], sent
    assert_equal [ "a.md", "alpha", "beta" ], @enq.flatten.find { |i| i[:id].end_with?("a.md") }[:sections]
    @enq.clear
    run_job
    assert_empty @enq
  end

  test "touching one file sends only that file" do
    run_job
    @enq.clear
    File.write(File.join(@dir, "b.txt"), "gamma changed")
    run_job
    assert_equal %w[b.txt], sent
  end

  test "vanished file is deleted and dropped from the manifest" do
    run_job
    File.delete(File.join(@dir, "b.txt"))
    run_job
    assert_equal [ [ SemanticSearch.kb_id(@user.id, 0, "b.txt") ] ], @del
    assert_equal 1, SemanticIndexEntry.where(user_id: @user.id).count
  end

  test "failed enqueue leaves the manifest untouched" do
    SemanticSearch.stub(:enabled?, true) do
      SemanticSearch.stub(:enqueue, ->(_) { nil }) do
        KbSource.stub(:list, [ { path: @dir, label: "t" } ]) { SemanticIndexJob.perform_now(@user.id) }
      end
    end
    assert_equal 0, SemanticIndexEntry.where(user_id: @user.id).count
  end

  test "bust_cache! enqueues the delta when enabled" do
    SemanticSearch.stub(:enabled?, true) do
      assert_enqueued_with(job: SemanticIndexJob, args: [ @user.id ]) { Kb::TreeBuilder.bust_cache!(@user) }
    end
    SemanticSearch.stub(:enabled?, false) do
      assert_no_enqueued_jobs(only: SemanticIndexJob) { Kb::TreeBuilder.bust_cache!(@user) }
    end
  end

  test "a new sidecar index_id clears the manifest and resends everything" do
    h = { "model" => "m", "index_model" => "m", "queued" => 0 }
    run_job(health: h.merge("index_id" => "one"))
    @enq.clear
    run_job(health: h.merge("index_id" => "one"))
    assert_empty @enq
    run_job(health: h.merge("index_id" => "two"))
    assert_equal %w[a.md b.txt], sent
  end

  test "index_model mismatch runs a rebuild that drains before committing" do
    calls = []
    healths = [ { "model" => "new", "index_model" => "old", "rebuilding" => false }, { "queued" => 0 }, { "index_id" => "x" } ]
    SemanticSearch.stub(:health, -> { healths.shift || { "queued" => 0 } }) do
      SemanticSearch.stub(:rebuild!, -> { calls << :rebuild; {} }) do
        SemanticSearch.stub(:rebuild_commit!, -> { calls << :commit; {} }) do
          SemanticSearch.stub(:rebuild_abort!, -> { calls << :abort; {} }) do
            SemanticSearch.stub(:prune, {}) { run_job_inner }
          end
        end
      end
    end
    assert_equal %i[rebuild commit], calls
    assert_equal %w[a.md b.txt], sent.grep(/\.(md|txt)\z/) # record sweep ids ride along
  end

  test "failed rebuild aborts the shadow" do
    calls = []
    SemanticSearch.stub(:health, { "model" => "new", "index_model" => "old" }) do
      SemanticSearch.stub(:rebuild!, {}) do
        SemanticSearch.stub(:rebuild_abort!, -> { calls << :abort; {} }) do
          SemanticSearch.stub(:enabled?, true) do
            SemanticSearch.stub(:enqueue, nil) { KbSource.stub(:list, [ { path: @dir, label: "t" } ]) { SemanticIndexJob.perform_now(@user.id) } }
          end
        end
      end
    end
    assert_equal %i[abort], calls
  end

  test "a capped walk does not delete entries beyond the cap" do
    run_job
    File.delete(File.join(@dir, "b.txt"))
    Dir.mkdir(File.join(@dir, "d"))
    cap = KbEntrySearch::SEARCH_VISIT_CAP
    silence_warnings { KbEntrySearch.const_set(:SEARCH_VISIT_CAP, 0) }
    begin
      run_job
    ensure
      silence_warnings { KbEntrySearch.const_set(:SEARCH_VISIT_CAP, cap) }
    end
    assert_empty @del
  end
end
