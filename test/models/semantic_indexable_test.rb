require "test_helper"

class SemanticIndexableTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @idea = @user.ideas.create!(title: "Zebrafish tracker", tldr: "tank logger")
    clear_enqueued_jobs
  end

  def jobs(&block)
    SemanticSearch.stub(:enabled?, true, &block)
    enqueued_jobs.select { |j| j["job_class"] == "SemanticRecordIndexJob" }.map { |j| j["arguments"] }
  end

  def run_jobs
    sent = []
    SemanticSearch.stub(:enabled?, true) do
      SemanticSearch.stub(:enqueue, ->(items) { sent.concat(items) }) do
        perform_enqueued_jobs(only: SemanticRecordIndexJob) { yield }
      end
    end
    sent
  end

  test "idea create enqueues itself" do
    args = jobs { @user.ideas.create!(title: "Another") }
    assert_equal [ [ "Idea", Idea.last.id, @user.id ] ], args
  end

  test "disabled enqueues nothing" do
    SemanticSearch.stub(:enabled?, false) { @idea.notes.create!(body: "x") }
    assert_empty enqueued_jobs.select { |j| j["job_class"] == "SemanticRecordIndexJob" }
  end

  test "note create enqueues the note and its idea" do
    note = nil
    args = jobs { note = @idea.notes.create!(body: "gill count") }
    assert_equal [ [ "Note", note.id, @user.id ], [ "Idea", @idea.id, @user.id ] ].sort_by(&:to_s), args.sort_by(&:to_s)
  end

  test "todo update fans out to the idea" do
    todo = @idea.todo_items.create!(title: "feed fish")
    clear_enqueued_jobs
    args = jobs { todo.update!(title: "feed fish twice") }
    assert_includes args, [ "Idea", @idea.id, @user.id ]
  end

  test "destroying a note enqueues a delete that still knows the owner" do
    note = @idea.notes.create!(body: "gill count")
    clear_enqueued_jobs
    jobs { note.destroy }
    sent = run_jobs { SemanticRecordIndexJob.perform_now("Note", note.id, @user.id) }
    assert_equal [ { id: "u#{@user.id}:note:#{note.id}", sections: [] } ], sent
  end

  test "idea sections are split per paragraph, note and tag; discarded ideas have none" do
    @idea.update!(description: "<div>first para</div><div>second para</div>")
    @idea.notes.create!(body: "a note")
    @idea.themes << @user.themes.create!(name: "Aquatic")
    sections = @idea.reload.semantic_sections
    assert_includes sections, "Zebrafish tracker - tank logger"
    assert_includes sections, "a note"
    assert_includes sections, "Aquatic"
    assert sections.any? { |s| s.include?("first para") }
    @idea.update!(discarded_at: Time.current)
    assert_empty @idea.reload.semantic_sections
  end

  test "theme rename reindexes linked ideas, other edits do not" do
    theme = @user.themes.create!(name: "Aquatic")
    @idea.themes << theme
    clear_enqueued_jobs
    args = jobs { theme.update!(color: "#d4953a") }
    assert_not_includes args, [ "Idea", @idea.id, @user.id ]
    clear_enqueued_jobs
    args = jobs { theme.update!(name: "Marine") }
    assert_includes args, [ "Idea", @idea.id, @user.id ]
  end

  test "topology rename reindexes linked ideas" do
    topo = @user.topologies.create!(name: "Tools", topology_type: :custom)
    @idea.topologies << topo
    clear_enqueued_jobs
    args = jobs { topo.update!(name: "Gear") }
    assert_includes args, [ "Idea", @idea.id, @user.id ]
  end

  test "job sends sections for a live record and empty for a missing one" do
    note = @idea.notes.create!(body: "gill count")
    sent = run_jobs do
      SemanticRecordIndexJob.perform_now("Note", note.id, @user.id)
      SemanticRecordIndexJob.perform_now("Note", 0, @user.id)
    end
    assert_equal [ { id: "u#{@user.id}:note:#{note.id}", sections: [ "gill count" ] }, { id: "u#{@user.id}:note:0", sections: [] } ], sent
  end

  test "sweep_records enqueues every record and prunes per type" do
    @idea.notes.create!(body: "gill count")
    enq = []
    pruned = []
    SemanticSearch.stub(:enqueue, ->(items) { enq.concat(items) }) do
      SemanticSearch.stub(:prune, ->(prefix, keep) { pruned << [ prefix, keep ] }) do
        assert SemanticIndex.sweep_records(@user)
      end
    end
    assert(enq.any? { |i| i[:id] == "u#{@user.id}:idea:#{@idea.id}" })
    assert(pruned.assoc("u#{@user.id}:note:"))
    assert_includes SemanticIndex.all_ids(@user), "u#{@user.id}:idea:#{@idea.id}"
  end
end
