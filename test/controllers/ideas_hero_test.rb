require "test_helper"

class IdeasHeroTest < ActionDispatch::IntegrationTest
  setup do
    @idea = User.first.ideas.create!(title: "Hero", state: :idea_new)
  end

  def upload(name) = fixture_file_upload("ocr_sample.png", "image/png").tap { |f| f.instance_variable_set(:@original_filename, name) }

  test "uploading more images appends and never wipes existing ones" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("a.png") ] } }
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("b.png"), upload("c.png") ] } }

    assert_equal 3, @idea.reload.hero_images.count
  end

  test "reorders mixed items and removes a single one" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("a.png"), upload("b.png") ] } }
    a, b = @idea.reload.hero_images.map(&:blob_id)
    d = Drawing.create!(idea: @idea, title: "d", role: :hero, content: { "elements" => [] })

    patch idea_path(@idea), params: { idea: { title: "Hero", hero_order: [ "", "image:#{b}", "drawing:#{d.id}", "image:#{a}" ] } }
    assert_equal [ "image:#{b}", "drawing:#{d.id}", "image:#{a}" ], @idea.reload.hero_items.map(&:key)

    patch idea_path(@idea), params: { idea: { title: "Hero", remove_hero_image_ids: [ b.to_s ], hero_order: [ "", "drawing:#{d.id}", "image:#{a}" ] } }
    assert_equal [ "drawing:#{d.id}", "image:#{a}" ], @idea.reload.hero_items.map(&:key)
  end

  test "show renders a mosaic for several hero items" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("a.png"), upload("b.png") ] } }
    get idea_path(@idea)
    assert_select ".idea-hero-cap--mosaic[data-cells='2'] .idea-hero-cap__tile", 2
  end

  test "show renders a single full-bleed cap for one item" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("a.png") ] } }
    get idea_path(@idea)
    assert_select ".idea-hero-cap:not(.idea-hero-cap--mosaic) img", 1
  end

  test "edit form lists hero tiles with order inputs; new ideas are drafts so drawing is enabled" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("a.png") ] } }
    get edit_idea_path(@idea)
    assert_select ".hero-set__list .hero-item input[name='idea[hero_order][]']", 1
    get new_idea_path
    follow_redirect!
    assert_select ".hero-set__actions button:not([disabled])", text: /Add drawing/
  end

  test "foreign blob and drawing ids in hero_order and remove_hero_image_ids are ignored" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("a.png") ] } }
    other = User.first.ideas.create!(title: "Other", state: :idea_new)
    other.hero_images.attach(io: File.open(file_fixture("ocr_sample.png")), filename: "theirs.png", content_type: "image/png")
    theirs = other.hero_images.first.blob_id
    foreign_drawing = Drawing.create!(idea: other, title: "x", role: :hero, content: { "elements" => [] })
    mine = @idea.reload.hero_images.first.blob_id

    patch idea_path(@idea), params: { idea: { title: "Hero", remove_hero_image_ids: [ theirs.to_s ],
                                              hero_order: [ "image:#{theirs}", "drawing:#{foreign_drawing.id}", "image:#{mine}" ] } }

    assert_equal [ "image:#{mine}" ], @idea.reload.hero_items.map(&:key)
    assert_equal 1, other.reload.hero_images.count
    assert_equal [ "image:#{theirs}", "drawing:#{foreign_drawing.id}", "image:#{mine}" ], @idea.hero_order # stale keys are stored but never rendered
  end

  test "saving again with no uploads adds nothing" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ upload("a.png") ] } }
    2.times { patch idea_path(@idea), params: { idea: { title: "Hero again" } } }
    assert_equal 1, @idea.reload.hero_images.count
  end

  test "a bad signed id is a form error, not a 500, and the idea is unchanged" do
    patch idea_path(@idea), params: { idea: { title: "Changed", hero_images: [ "not-a-signed-id" ] } }

    assert_response :unprocessable_content
    assert_select ".alert-error", /hero images/i
    assert_equal "Hero", @idea.reload.title
    assert_equal 0, @idea.hero_images.count
  end

  test "non-image uploads are rejected with a form error" do
    patch idea_path(@idea), params: { idea: { title: "Hero", hero_images: [ fixture_file_upload("sample.pdf", "application/pdf") ] } }
    assert_response :unprocessable_content
    assert_equal 0, @idea.reload.hero_images.count
  end
end
