require "test_helper"

class IdeaHeroTest < ActiveSupport::TestCase
  setup { @idea = User.first.ideas.create!(title: "Hero", state: :idea_new) }

  def png(name) = { io: File.open(file_fixture("ocr_sample.png")), filename: name, content_type: "image/png" }

  def draw(title) = Drawing.create!(idea: @idea, title: title, role: :hero, content: { "elements" => [] })

  test "hero_items interleaves images and drawings by hero_order, tolerating stale keys" do
    @idea.hero_images.attach(png("a.png"), png("b.png"))
    d = draw("sketch")
    a, b = @idea.hero_images.map { |x| "image:#{x.blob_id}" }
    @idea.update!(hero_order: [ "image:0", b, "drawing:#{d.id}", a, "bogus", b ])

    assert_equal [ b, "drawing:#{d.id}", a ], @idea.hero_items.map(&:key)
  end

  test "items missing from hero_order trail in creation order" do
    @idea.hero_images.attach(png("a.png"))
    d = draw("sketch")
    @idea.update!(hero_order: [ "drawing:#{d.id}" ])
    @idea.hero_images.attach(png("c.png"))

    assert_equal [ :drawing, :image, :image ], @idea.reload.hero_items.map(&:kind)
  end

  test "attaching more hero images appends" do
    @idea.hero_images.attach(png("a.png"))
    @idea.update!(hero_images: [ png("b.png") ])
    assert_equal 2, @idea.reload.hero_images.count
  end

  test "legacy hero_image attachment rows are migrated by renaming" do
    @idea.hero_images.attach(png("legacy.png"))
    ActiveStorage::Attachment.where(record: @idea).update_all(name: "hero_image")
    ActiveRecord::Base.connection.execute("UPDATE active_storage_attachments SET name = 'hero_images' WHERE record_type = 'Idea' AND name = 'hero_image'")

    assert_equal [ "legacy.png" ], @idea.reload.hero_items.map(&:title)
  end

  test "removing an image via remove_hero_image_ids purges it" do
    @idea.hero_images.attach(png("a.png"), png("b.png"))
    gone = @idea.hero_images.first.blob_id
    @idea.update!(remove_hero_image_ids: [ gone.to_s ])
    assert_equal 1, @idea.reload.hero_images.count
    assert_not_includes @idea.hero_images.map(&:blob_id), gone
  end

  test "drawings without a png are not renderable" do
    draw("blank")
    assert_not @idea.hero_media?
    assert_equal 1, @idea.hero_items.size
  end
end
