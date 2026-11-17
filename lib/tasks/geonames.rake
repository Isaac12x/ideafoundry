require "fileutils"
require "net/http"

# Offline reverse geocoding data (GeoNames, CC-BY 4.0). Used by ReverseGeocoder.
namespace :geonames do
  desc "Download GeoNames cities + country/admin1 names into storage/geonames (GEONAMES_DATASET, FORCE=1)"
  task install: :environment do
    base = "https://download.geonames.org/export/dump"
    dataset = ENV.fetch("GEONAMES_DATASET", "cities1000")
    dir = Pathname(ENV.fetch("GEONAMES_DIR", Rails.root.join("storage/geonames").to_s))
    force = ENV["FORCE"] == "1"
    FileUtils.mkdir_p(dir)

    fetch = lambda do |name, &finish|
      target = dir.join(name.sub(/\.zip\z/, ".txt"))
      next puts("geonames: #{target.basename} present") if target.exist? && !force
      tmp = Pathname("#{target}.tmp")
      body = Net::HTTP.get_response(URI("#{base}/#{name}"))
      raise "GET #{name}: HTTP #{body.code}" unless body.is_a?(Net::HTTPSuccess)
      tmp.binwrite(body.body)
      finish&.call(tmp)
      File.rename(tmp, target)
      puts "geonames: installed #{target.basename} (#{target.size / 1024} KB)"
    end

    begin
      fetch.call("#{dataset}.zip") do |tmp|
        Zip::File.open(tmp.to_s) { |z| File.binwrite(tmp, z.find_entry("#{dataset}.txt").get_input_stream.read) }
      end
      fetch.call("countryInfo.txt")
      fetch.call("admin1CodesASCII.txt")
    rescue StandardError => e
      FileUtils.rm_f(Dir[dir.join("*.tmp")])
      abort "geonames: install failed (#{e.message}); reverse geocoding falls back to coordinates"
    end
  end
end
