# Offline reverse geocoding against GeoNames dumps (storage/geonames, see `rake geonames:install`).
# Coordinates never leave the machine. Data © GeoNames, CC-BY 4.0.
# ponytail: linear scan with a latitude pre-filter, fine for ~150k rows (cities1000);
# switch to a k-d tree / grid index if the dataset grows to allCountries.
module ReverseGeocoder
  MAX_KM = 50.0
  KM_PER_DEG = 111.195
  Data = Struct.new(:lat, :lng, :name, :country, :admin1, :countries, :admins)

  @mutex = Mutex.new
  @data = nil

  class << self
    def lookup(lat, lng)
      d = data or return nil
      lat = Float(lat)
      lng = Float(lng)
      cos = Math.cos(lat * Math::PI / 180)
      best_i = nil
      best = MAX_KM
      d.lat.each_with_index do |plat, i|
        dy = (plat - lat).abs * KM_PER_DEG
        next if dy > best
        dlng = (d.lng[i] - lng).abs
        dlng = 360 - dlng if dlng > 180
        dist = Math.hypot(dy, dlng * KM_PER_DEG * cos)
        next unless dist < best
        best = dist
        best_i = i
      end
      best_i && build(d, best_i)
    end

    def reset!
      @mutex.synchronize { @data = nil }
    end

    private

    def build(d, i)
      cc = d.country[i]
      name = d.name[i]
      admin1 = d.admins["#{cc}.#{d.admin1[i]}"]
      admin1 = nil if admin1 == name
      country = d.countries[cc]
      { name:, admin1:, country:, label: [ name, admin1, country ].compact.join(", ") }
    end

    def data
      @data || @mutex.synchronize { @data ||= load_data || (return nil) }
    end

    def dir
      Pathname(ENV.fetch("GEONAMES_DIR") { Rails.root.join("storage/geonames").to_s })
    end

    def load_data
      cities = dir.join("#{ENV.fetch('GEONAMES_DATASET', 'cities1000')}.txt")
      return nil unless cities.exist?
      d = Data.new([], [], [], [], [], {}, {})
      File.foreach(cities, encoding: "UTF-8") do |line|
        f = line.split("\t", 12)
        d.name << f[1]
        d.lat << f[4].to_f
        d.lng << f[5].to_f
        d.country << f[8]
        d.admin1 << f[10]
      end
      each_row("countryInfo.txt") { |f| d.countries[f[0]] = f[4] }
      each_row("admin1CodesASCII.txt") { |f| d.admins[f[0]] = f[1] }
      d
    end

    def each_row(file)
      path = dir.join(file)
      return unless path.exist?
      File.foreach(path, encoding: "UTF-8") do |line|
        next if line.start_with?("#")
        yield line.chomp.split("\t")
      end
    end
  end
end
