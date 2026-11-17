require "test_helper"

class ReverseGeocodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @old = ENV["GEONAMES_DIR"]
    ENV["GEONAMES_DIR"] = file_fixture("geonames").to_s
    ReverseGeocoder.reset!
  end

  teardown do
    ENV["GEONAMES_DIR"] = @old
    ReverseGeocoder.reset!
  end

  test "returns label" do
    get reverse_geocode_path, params: { lat: 51.5072, lng: -0.1276 }
    assert_response :success
    assert_equal "London, England, United Kingdom", response.parsed_body["label"]
  end

  test "null label when no match" do
    get reverse_geocode_path, params: { lat: 0, lng: 0 }
    assert_response :success
    assert_nil response.parsed_body["label"]
  end

  test "422 on bad coordinates" do
    [ {}, { lat: "x", lng: 1 }, { lat: 91, lng: 0 }, { lat: 0, lng: 181 } ].each do |p|
      get reverse_geocode_path, params: p
      assert_response :unprocessable_entity
    end
  end
end
