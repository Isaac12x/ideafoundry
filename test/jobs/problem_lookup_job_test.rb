require "test_helper"

class ProblemLookupJobTest < ActiveJob::TestCase
  SEARCH = { query: { search: [ { title: "Slippery rail" } ] } }.to_json
  PAGES = { query: { pages: { "1" => { extract: "Intro line.\n\n== Causes ==\nLeaves.", fullurl: "https://en.wikipedia.org/wiki/Slippery_rail" } } } }.to_json
  TYPEAHEAD = { results: [ { slug: "Slippery_rail", title: "Slippery rail", snippet: "A condition." } ] }.to_json
  GROK = "<html><article><h1>Slippery rail</h1><h2>Causes</h2><p>#{'Leaves on the line. ' * 20}</p></article></html>".freeze

  setup do
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @problem = @user.problems.create!(title: "Slippery train tracks #{SecureRandom.hex(3)}", need: "Trains slide.")
    FileUtils.rm_rf(@problem.abs_dir)
  end

  teardown { FileUtils.rm_rf(@problem.abs_dir) }

  def fake(grok: GROK)
    lambda do |url|
      case url
      when /wikipedia.*list=search/ then SEARCH
      when /wikipedia/ then PAGES
      when /typeahead/ then TYPEAHEAD
      else raise "HTTP 500" unless grok; grok
      end
    end
  end

  test "imports both articles with sidecars and links them from problem.md" do
    Kb::ProblemResearch.stub(:get, fake) { ProblemLookupJob.perform_now(@problem.id) }

    assert_equal "done", @problem.reload.status
    wiki = File.join(@problem.abs_dir, "Wikipedia - Slippery rail.md")
    assert_includes File.read(wiki), "## Causes"
    assert_equal "https://en.wikipedia.org/wiki/Slippery_rail", Kb::Source.read(wiki)["url"]
    assert_equal "https://grokipedia.com/page/Slippery_rail", Kb::Source.read(File.join(@problem.abs_dir, "Grokipedia - Slippery rail.md"))["url"]
    md = File.read(File.join(@problem.abs_dir, "problem.md"))
    assert_includes md, "Trains slide."
    assert_includes md, "(Wikipedia%20-%20Slippery%20rail.md)"
  end

  test "one site failing still imports the other; rerun does not duplicate links" do
    Kb::ProblemResearch.stub(:get, fake(grok: nil)) { 2.times { ProblemLookupJob.perform_now(@problem.id) } }

    assert_equal "done", @problem.reload.status
    assert_match(/Wikipedia/, @problem.result)
    assert_no_match(/Grokipedia/, @problem.result)
    assert_equal 1, File.read(File.join(@problem.abs_dir, "problem.md")).scan("Wikipedia%20-").size
  end

  test "creating via the controller queues the job" do
    assert_enqueued_with(job: ProblemLookupJob) { @problem.find_sources! }
    assert_equal "pending", @problem.status
  end
end
