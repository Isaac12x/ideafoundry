require "test_helper"

class Kb::ProjectRequirementsTest < ActiveSupport::TestCase
  setup do
    @base = Dir.mktmpdir
    @project = Kb::Project.create!(base: @base, parent_rel: "", name: "Ferment")
    @test = @project.create_test!(name: "Cold")
  end
  teardown { FileUtils.rm_rf(@base) }

  FakeImporter = Struct.new(:calls) do
    def call(url)
      calls << url
      { "url" => url, "host" => "example.org", "title" => "Cold chain", "excerpt" => "Keep it at 4C." }
    end
  end

  test "tokens become one reference each, links are imported inline, free text is kept" do
    importer = FakeImporter.new([])
    @test.add_requirements!("@[Heat pump · v3](idea:3) @[Rule](maxim:2) https://example.org/a.", importer: importer)
    @test.add_requirements!("a plain need")

    reqs = Kb::ProjectTest.new(@base, @test.rel, @project).requirements
    assert_equal %w[ref ref import text], reqs.map { |r| r["kind"] }
    assert_equal "@[Heat pump · v3](idea:3)", reqs[0]["text"]
    imported = reqs[2]
    assert_equal [ "Cold chain", "Keep it at 4C.", "example.org", "https://example.org/a" ], imported.values_at("text", "excerpt", "host", "url")
    assert_equal [ "https://example.org/a" ], importer.calls
  end

  test "free text typed beside tokens and links stays as a plain note" do
    importer = FakeImporter.new([])
    @test.add_requirements!("needs a fridge @[Rule](maxim:2) see https://example.org/a.", importer: importer)
    reqs = @test.requirements
    assert_equal %w[text ref import], reqs.map { |r| r["kind"] }
    assert_equal "needs a fridge see", reqs[0]["text"]
  end

  test "bare tokens leave no empty note" do
    @test.add_requirements!("@[Rule](maxim:2), @[Heat](idea:3)")
    assert_equal %w[ref ref], @test.requirements.map { |r| r["kind"] }
  end

  test "remove and blank handling" do
    item = @test.add_requirements!("need").first
    assert_raises(ArgumentError) { @test.add_requirements!("  ") }
    assert_raises(ArgumentError) { @test.remove_requirement!("nope") }
    @test.remove_requirement!(item["id"])
    assert_empty @test.requirements
  end

  test "an import failure is reported and nothing is stored" do
    failing = Object.new
    def failing.call(_) = raise(Kb::UrlImport::Error, "That address is private.")
    error = assert_raises(ArgumentError) { @test.add_requirements!("http://10.0.0.1/x", importer: failing) }
    assert_match(/private/, error.message)
    assert_empty @test.requirements
  end
end

class Kb::UrlImportTest < ActiveSupport::TestCase
  PAGE = "<html><head><title>Cold chain</title></head><body><article>#{'<p>Keep it at four degrees. </p>' * 40}</article></body></html>".freeze

  test "private and non-http targets are refused before any request" do
    %w[http://127.0.0.1/ http://10.1.2.3/x http://169.254.169.254/latest http://[::1]/ http://192.168.0.5/].each do |url|
      assert_raises(Kb::UrlImport::Error, url) { Kb::UrlImport.call(url) }
    end
    assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("file:///etc/passwd") }
    assert_raises(Kb::UrlImport::Error) { Kb::UrlImport.call("ftp://example.org/x") }
  end

  test "imports title and a bounded excerpt of a public page" do
    Kb::UrlImport.stub(:fetch, [ PAGE, "https://example.org/a" ]) do
      page = Kb::UrlImport.call("https://example.org/a")
      assert_equal "Cold chain", page["title"]
      assert_equal "example.org", page["host"]
      assert page["excerpt"].start_with?("Keep it at four degrees.")
      assert_operator page["excerpt"].length, :<=, Kb::UrlImport::EXCERPT_CHARS
    end
  end

  test "private? covers loopback, link-local, ULA and CGNAT" do
    %w[127.0.0.1 10.0.0.1 172.16.0.1 169.254.1.1 100.64.0.1 ::1 fd00::1 ::ffff:10.0.0.1].each { |ip| assert Kb::UrlImport.private?(ip), ip }
    assert_not Kb::UrlImport.private?("93.184.216.34")
  end
end
