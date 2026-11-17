require "test_helper"

class ReverseGeocoderTest < ActiveSupport::TestCase
  setup do
    @old = ENV["GEONAMES_DIR"]
    ENV["GEONAMES_DIR"] = file_fixture("geonames").to_s
    ReverseGeocoder.reset!
  end

  teardown do
    ENV["GEONAMES_DIR"] = @old
    ReverseGeocoder.reset!
  end

  test "nearest place with admin1 and country label" do
    r = ReverseGeocoder.lookup(41.4036, 2.1744)
    assert_equal "Gràcia", r[:name]
    assert_equal "Gràcia, Catalonia, Spain", r[:label]
    assert_equal "Barcelona, Catalonia, Spain", ReverseGeocoder.lookup(41.37, 2.16)[:label]
  end

  test "drops admin1 equal to name" do
    assert_equal "Madrid, Spain", ReverseGeocoder.lookup(40.4165, -3.7026)[:label]
  end

  test "london" do
    assert_equal "London, England, United Kingdom", ReverseGeocoder.lookup(51.5072, -0.1276)[:label]
  end

  test "nil beyond 50 km" do
    assert_nil ReverseGeocoder.lookup(41.9, 2.8) # Girona area, ~80 km from Barcelona
    assert_nil ReverseGeocoder.lookup(0, 0)
  end

  test "nil when data dir missing" do
    ENV["GEONAMES_DIR"] = Rails.root.join("tmp/no-geonames").to_s
    ReverseGeocoder.reset!
    assert_nil ReverseGeocoder.lookup(41.4, 2.17)
  end
end
