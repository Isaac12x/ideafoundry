require "test_helper"

class IdeaHistoryTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(email: "history@example.com", name: "History User")
    @idea = Idea.create!(
      user: @user,
      title: "History baseline",
      state: :idea_new,
      trl: 2,
      difficulty: 3,
      opportunity: 4,
      timing: 5,
      metadata: {
        "enrichment" => {
          "query" => "baseline",
          "summary" => "one result"
        },
        "custom_field" => "original"
      },
      napkin_calculations: {
        "rows" => 2,
        "cols" => 2,
        "cells" => {
          "A1" => { "raw" => "10" },
          "B1" => { "raw" => "=A1*2" }
        }
      }
    )
    @idea.description = "Baseline description"
    @idea.save!
  end

  test "snapshots and restores all idea owned content" do
    topology = @user.topologies.create!(name: "History Topology")
    list = @user.lists.create!(name: "History List", kind: :named)

    @idea.idea_topologies.create!(topology: topology)
    @idea.idea_lists.create!(list: list, position: 4)
    todo = @idea.todo_items.create!(title: "Baseline todo")
    note = @idea.notes.create!(body: "Baseline note")
    entry = @idea.idea_entries.create!(
      kind: :tool,
      name: "Baseline tool",
      url: "https://example.com/tool",
      description: "Tool notes"
    )
    drawing = @idea.drawings.create!(
      title: "Baseline drawing",
      role: :hero,
      position: 2,
      content: { "elements" => [{ "id" => "one" }] }
    )
    @idea.hero_image.attach(io: StringIO.new("hero-one"), filename: "hero-one.txt", content_type: "text/plain")
    @idea.attachments.attach(io: StringIO.new("attachment-one"), filename: "attachment-one.txt", content_type: "text/plain")
    drawing.rendered_png.attach(io: StringIO.new("png-one"), filename: "drawing-one.png", content_type: "image/png")

    version = @idea.create_version("Complete baseline")
    snapshot = version.snapshot_data

    assert_equal "original", snapshot.dig("metadata", "custom_field")
    assert_equal "10", snapshot.dig("napkin_calculations", "cells", "A1", "raw")
    assert_equal [todo.title], snapshot["todo_items"].map { |item| item["title"] }
    assert_equal [note.body], snapshot["notes"].map { |item| item["body"] }
    assert_equal [entry.name], snapshot["idea_entries"].map { |item| item["name"] }
    assert_equal [drawing.title], snapshot["drawings"].map { |item| item["title"] }
    assert_equal [topology.id], snapshot["topology_ids"]
    assert_equal [list.id], snapshot["list_memberships"].map { |item| item["list_id"] }
    assert_equal @idea.hero_image.blob_id, snapshot.dig("media", "hero_image", "blob_id")
    assert_equal [@idea.attachments.first.blob_id], snapshot.dig("media", "attachments").map { |item| item["blob_id"] }
    assert_equal drawing.rendered_png.blob_id, snapshot.dig("drawings", 0, "rendered_png", "blob_id")

    @idea.update!(
      title: "Mutated title",
      trl: 8,
      metadata: { "custom_field" => "changed" },
      napkin_calculations: { "rows" => 1, "cols" => 1, "cells" => { "A1" => { "raw" => "99" } } }
    )
    @idea.description = "Mutated description"
    @idea.save!
    @idea.idea_topologies.destroy_all
    @idea.idea_lists.destroy_all
    @idea.todo_items.destroy_all
    @idea.notes.destroy_all
    @idea.idea_entries.destroy_all
    @idea.drawings.destroy_all
    @idea.hero_image.detach
    @idea.attachments.detach

    version.restore_to_idea!
    @idea.reload

    assert_equal "History baseline", @idea.title
    assert_equal 2, @idea.trl
    assert_equal "Baseline description", @idea.description.to_plain_text
    assert_equal "original", @idea.metadata["custom_field"]
    assert_equal "10", @idea.napkin_calculations.dig("cells", "A1", "raw")
    assert_equal [topology.id], @idea.topology_ids
    assert_equal [list.id], @idea.idea_lists.map(&:list_id)
    assert_equal ["Baseline todo"], @idea.todo_items.map(&:title)
    assert_equal ["Baseline note"], @idea.notes.map(&:body)
    assert_equal ["Baseline tool"], @idea.idea_entries.map(&:name)
    assert_equal ["Baseline drawing"], @idea.drawings.map(&:title)
    assert @idea.hero_image.attached?
    assert_equal "hero-one.txt", @idea.hero_image.filename.to_s
    assert_equal ["attachment-one.txt"], @idea.attachments.map { |attachment| attachment.filename.to_s }
    assert @idea.drawings.first.rendered_png.attached?
  end

  test "direct idea updates create a history version with calculations metadata and scores" do
    initial_count = @idea.versions.count

    @idea.update!(
      trl: 9,
      metadata: { "enrichment" => { "summary" => "updated" } },
      napkin_calculations: { "rows" => 1, "cols" => 1, "cells" => { "A1" => { "raw" => "42" } } }
    )

    assert_equal initial_count + 1, @idea.versions.count
    snapshot = @idea.latest_version.snapshot_data
    assert_equal 9, snapshot["trl"]
    assert_equal @idea.computed_score, snapshot["computed_score"]
    assert_equal "updated", snapshot.dig("metadata", "enrichment", "summary")
    assert_equal "42", snapshot.dig("napkin_calculations", "cells", "A1", "raw")
  end

  test "idea owned record and media changes create history versions" do
    initial_count = @idea.versions.count

    @idea.todo_items.create!(title: "Recorded todo")
    assert_equal initial_count + 1, @idea.versions.count
    assert_equal ["Recorded todo"], @idea.latest_version.snapshot_data["todo_items"].map { |item| item["title"] }

    @idea.notes.create!(body: "Recorded note")
    assert_equal initial_count + 2, @idea.versions.count
    assert_equal ["Recorded note"], @idea.latest_version.snapshot_data["notes"].map { |item| item["body"] }

    @idea.idea_entries.create!(kind: :competitor, name: "Recorded competitor")
    assert_equal initial_count + 3, @idea.versions.count
    assert_equal ["Recorded competitor"], @idea.latest_version.snapshot_data["idea_entries"].map { |item| item["name"] }

    @idea.drawings.create!(title: "Recorded drawing", content: { "elements" => [] })
    assert_equal initial_count + 4, @idea.versions.count
    assert_equal ["Recorded drawing"], @idea.latest_version.snapshot_data["drawings"].map { |item| item["title"] }

    @idea.attachments.attach(io: StringIO.new("recorded-media"), filename: "recorded-media.txt", content_type: "text/plain")
    assert_equal initial_count + 5, @idea.versions.count
    assert_equal ["recorded-media.txt"], @idea.latest_version.snapshot_data.dig("media", "attachments").map { |item| item["filename"] }
  end
end
