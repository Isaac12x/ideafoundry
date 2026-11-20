require "test_helper"

class SemanticIndexTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @idea = @user.ideas.create!(title: "Zebrafish tracker")
  end

  # One built record per registered type; every item must render a title and a url.
  def build_all
    list = @user.lists.create!(name: "Reading", kind: "named")
    topo = @user.topologies.create!(name: "Tools", topology_type: :custom)
    lic = @idea.licensors.create!(company: "Acme")
    dl = @user.kb_downloads.create!(url: "https://example.com/v", source_index: 0, dir: "", status: "done", filename: "v.mp4", title: "A video", transcript: "00:01 - hello")
    {
      "idea" => @idea,
      "note" => @idea.notes.create!(body: "gill count"),
      "todo" => @idea.todo_items.create!(title: "feed fish"),
      "list" => list,
      "list_item" => list.list_items.create!(title: "Book"),
      "topology" => topo,
      "theme" => @user.themes.create!(name: "Aquatic"),
      "problem" => @user.problems.create!(title: "Leaky tank", folder: "leaky"),
      "fact" => @user.facts.create!(body: "Fish sleep"),
      "maxim" => @user.maxims.create!(body: "Keep it simple"),
      "submission" => @user.submissions.create!(title: "Inbound", body: "text"),
      "template" => @user.templates.create!(name: "Basic", field_definitions: [], section_order: []),
      "agent_thread" => @user.agent_threads.create!(title: "Question"),
      "agent_recommendation" => @user.agent_recommendations.create!(action: "update_idea", risk_level: "low", reasoning: "because"),
      "kb_annotation" => @user.kb_annotations.create!(source_path: "/tmp/kb", relative_path: "a.md", quote: "q", start_offset: 0, end_offset: 1),
      "kb_bookmark" => @user.kb_bookmarks.create!(source_path: "/tmp/kb", relative_path: "a.pdf", label: "p1", page: 1),
      "licensor" => lic,
      "licensor_contact" => lic.contacts.create!(channel: :call, summary: "called"),
      "media_digest" => MediaDigest.record!(user: @user, kb_download: dl, body: "digest body"),
      "drawing" => @idea.drawings.create!(title: "Sketch", content: { "elements" => [ { "text" => "box" } ] }),
      "idea_entry" => @idea.idea_entries.create!(name: "Rival", kind: :competitor),
      "kb_download" => dl,
      "build_item" => @user.build_items.create!(title: "Ship it")
    }
  end

  test "every registered type except attachment renders an item and has sections" do
    records = build_all
    assert_equal SemanticIndex::TYPES.keys - [ "attachment" ], records.keys
    records.each do |type, rec|
      item = SemanticIndex.item(type, rec)
      assert item[:title].present?, "#{type} title"
      assert item[:url].to_s.start_with?("/"), "#{type} url #{item[:url].inspect}"
      assert_equal type, rec.semantic_type
      assert rec.semantic_sections.any?, "#{type} sections" unless type == "kb_annotation" || type == "kb_bookmark"
    end
  end

  test "scopes find the records and only the owner's" do
    records = build_all
    other = users(:two)
    records.each do |type, rec|
      assert SemanticIndex.records(@user, type, [ rec.id ]).key?(rec.id.to_s), "#{type} visible to owner"
      assert_empty SemanticIndex.records(other, type, [ rec.id ]), "#{type} hidden from others"
    end
  end

  test "attachment ocr text is indexed for idea attachments" do
    @idea.attachments.attach(io: StringIO.new("x"), filename: "scan.png", content_type: "image/png")
    att = @idea.attachments_attachments.first
    att.update!(ocr_text: "invoice total")
    assert_equal [ "scan.png", "invoice total" ], att.semantic_sections
    assert SemanticIndex.records(@user, "attachment", [ att.id ]).key?(att.id.to_s)
    assert_equal idea_path_for(@idea), SemanticIndex.item("attachment", att)[:url]
  end

  test "split packs paragraphs and caps size" do
    assert_equal [ "a b" ], SemanticIndex.split("a\n\nb")
    assert_equal 3, SemanticIndex.split(([ "x" * 600 ] * 3).join("\n\n"), size: 700).size
  end

  test "parse only accepts the user's own registered record ids" do
    assert_equal [ "note", "5" ], SemanticIndex.parse(@user, "u#{@user.id}:note:5")
    assert_nil SemanticIndex.parse(@user, "u#{@user.id + 1}:note:5")
    assert_nil SemanticIndex.parse(@user, "u#{@user.id}:kb:0:a.md")
  end

  def idea_path_for(idea) = Rails.application.routes.url_helpers.idea_path(idea)
end
