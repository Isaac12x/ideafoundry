require "test_helper"

class Kb::MediaTypesTest < ActiveSupport::TestCase
  test "kinds for the viewer formats" do
    {
      "a.gif" => :image, "a.SVG" => :image, "a.avif" => :image, "a.bmp" => :image, "a.ico" => :image,
      "a.stl" => :model, "a.glb" => :model, "a.STEP" => :model, "a.igs" => :model,
      "a.f3d" => :cad, "a.sldprt" => :cad, "a.blend" => :cad,
      "a.zip" => :archive, "a.7z" => :archive, "a.tgz" => :archive, "a.tar.gz" => :archive, "a.gz" => :generic,
      "a.cbz" => :comic, "a.cbr" => :comic,
      "a.epub" => :book, "a.mobi" => :book, "a.azw3" => :book, "a.djvu" => :book,
      "a.heic" => :generic, "a.rb" => :generic
    }.each { |name, kind| assert_equal kind, Kb::MediaTypes.kind_for(name), name }
  end

  test "animated and vector images get image mime types and stay out of OCR" do
    assert_equal "image/gif", Kb::MediaTypes.mime_type_for("x.gif")
    assert_equal "image/svg+xml", Kb::MediaTypes.mime_type_for("x.svg")
    assert_not_includes Kb::MediaTypes::OCR_EXTENSIONS, ".svg"
  end

  test "every cad extension has a hint and every viewer extension is creatable" do
    assert_equal Kb::MediaTypes::CAD_EXTENSIONS.sort, Kb::MediaTypes::CAD_HINTS.keys.sort
    assert_empty Kb::MediaTypes::VIEWER_EXTENSIONS - KbController::ALL_EXTENSIONS
  end
end
