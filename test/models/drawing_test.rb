require "test_helper"

class DrawingTest < ActiveSupport::TestCase
  def setup
    @user = User.first
    @idea = @user.ideas.create!(title: "Drawing Host", state: :idea_new)
  end

  test "is valid with title and content" do
    d = Drawing.new(idea: @idea, title: "T", content: { "elements" => [], "appState" => {}, "files" => {} })
    assert d.valid?
  end

  test "requires a title" do
    d = Drawing.new(idea: @idea, title: "", content: { "elements" => [] })
    assert_not d.valid?
    assert_includes d.errors[:title], "can't be blank"
  end

  test "requires content" do
    d = Drawing.new(idea: @idea, title: "T", content: nil)
    assert_not d.valid?
    assert_includes d.errors[:content], "can't be blank"
  end

  test "serializes content as JSON round-trip" do
    payload = {
      "elements" => [{ "id" => "abc", "type" => "rectangle", "x" => 1, "y" => 2 }],
      "appState" => { "viewBackgroundColor" => "#fff" },
      "files" => {}
    }
    d = Drawing.create!(idea: @idea, title: "RT", content: payload)
    fetched = Drawing.find(d.id)
    assert_equal payload, fetched.content
    assert_equal "abc", fetched.content["elements"].first["id"]
  end

  test "ordered scope returns by updated_at desc" do
    older = Drawing.create!(idea: @idea, title: "old", content: { "elements" => [] }, updated_at: 2.days.ago)
    newer = Drawing.create!(idea: @idea, title: "new", content: { "elements" => [] }, updated_at: 1.minute.ago)
    assert_equal [newer, older], @idea.drawings.ordered.to_a
  end

  test "deleting idea destroys drawings" do
    Drawing.create!(idea: @idea, title: "x", content: { "elements" => [] })
    assert_difference("Drawing.count", -@idea.drawings.count) do
      @idea.destroy
    end
  end

  test "defaults to general role" do
    d = Drawing.create!(idea: @idea, title: "T", content: { "elements" => [] })
    assert_equal "general", d.role
    assert d.general?
  end

  test "supports hero and attachment roles" do
    h = Drawing.create!(idea: @idea, title: "H", content: { "elements" => [] }, role: :hero)
    a = Drawing.create!(idea: @idea, title: "A", content: { "elements" => [] }, role: :attachment)
    assert h.hero?
    assert a.attachment?
    assert_equal h, @idea.hero_drawing
    assert_includes @idea.attachment_drawings, a
  end

  test "only one hero drawing per idea" do
    Drawing.create!(idea: @idea, title: "H1", content: { "elements" => [] }, role: :hero)
    second = Drawing.new(idea: @idea, title: "H2", content: { "elements" => [] }, role: :hero)
    assert_not second.valid?
    assert_includes second.errors[:role].join, "already used"
  end

  test "stores rendered_png when attached" do
    d = Drawing.create!(idea: @idea, title: "T", content: { "elements" => [] })
    d.rendered_png.attach(
      io: StringIO.new("\x89PNG\r\n\x1a\n"),
      filename: "thumb.png",
      content_type: "image/png"
    )
    assert d.rendered_png.attached?
    assert_match %r{/rails/}, d.png_url
  end

  test "general scope filters by role" do
    Drawing.create!(idea: @idea, title: "G", content: { "elements" => [] }, role: :general)
    Drawing.create!(idea: @idea, title: "H", content: { "elements" => [] }, role: :hero)
    titles = @idea.general_drawings.pluck(:title)
    assert_includes titles, "G"
    refute_includes titles, "H"
  end
end
