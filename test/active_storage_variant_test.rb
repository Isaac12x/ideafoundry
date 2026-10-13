require "test_helper"

# image_processing 2.x no longer pulls in ruby-vips/mini_magick; guard that variants still process.
class ActiveStorageVariantTest < ActiveSupport::TestCase
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")

  test "image variant is processed" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(PNG), filename: "p.png", content_type: "image/png")
    assert blob.variant(resize_to_limit: [ 10, 10 ]).processed.image.attached?
  ensure
    blob&.purge
  end
end
