require "test_helper"

class MoodImagesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.first || User.create!(email: "test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Vision Test")
  end

  def png
    fixture_file_upload_stub("a.png")
  end

  # Build an in-memory uploaded file without needing a fixture on disk.
  def fixture_file_upload_stub(name)
    Rack::Test::UploadedFile.new(StringIO.new("\x89PNG\r\n"), "image/png", original_filename: name)
  end

  test "uploads to the global board when no idea given" do
    assert_difference("MoodImage.count", 2) do
      post mood_images_path(format: :turbo_stream), params: { files: [png, png] }
    end
    assert_response :success
    assert_equal 2, @user.mood_images.global.count
    assert @user.mood_images.first.file.attached?
  end

  test "uploads to an idea board and cascades positions" do
    assert_difference("MoodImage.count", 2) do
      post mood_images_path(format: :turbo_stream), params: { idea_id: @idea.id, files: [png, png] }
    end
    imgs = @idea.mood_images.ordered.to_a
    assert_equal 2, imgs.size
    # Second tile is offset from the first so they don't stack exactly.
    refute_equal [imgs[0].pos_x, imgs[0].pos_y], [imgs[1].pos_x, imgs[1].pos_y]
  end

  test "update persists a moved position" do
    post mood_images_path(format: :turbo_stream), params: { idea_id: @idea.id, files: [png] }
    img = @idea.mood_images.first
    patch mood_image_path(img), params: { mood_image: { pos_x: 314, pos_y: 271, z_index: 9 } }
    assert_response :success
    img.reload
    assert_equal 314, img.pos_x
    assert_equal 9, img.z_index
  end

  test "destroy removes the image" do
    post mood_images_path(format: :turbo_stream), params: { files: [png] }
    img = @user.mood_images.first
    assert_difference("MoodImage.count", -1) do
      delete mood_image_path(img)
    end
    assert_response :success
  end
end
