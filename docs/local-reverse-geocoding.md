# Local Reverse Geocoding

Decision (2026-11-16): idea locations are named offline from the GeoNames dataset. Coordinates never leave the machine.

## Context

New ideas capture the browser's geolocation (`idea_location_controller.js`) and show a short place label ("Gràcia, Catalonia, Spain"). The first version asked OpenStreetMap's public Nominatim service for that label, which sent the user's coordinates to a third party with every new idea. That conflicts with the app's local-first stance (local Whisper, local audio API, local-only Excalidraw).

## Options considered

- **Public Nominatim**: street-level, zero setup, but leaks coordinates. Rejected.
- **Self-hosted Nominatim / Photon**: street-level and private, but needs a full OpenStreetMap import (tens to hundreds of GB, Postgres or Elasticsearch). Overkill for "where was I when I had this idea".
- **GeoNames `cities1000`** (CC-BY 4.0): every place with more than 1,000 people, about 150k rows (~10 MB zipped). Town or neighbourhood accuracy, a nearest-neighbour scan in Ruby. **Chosen.**

## How it works

- `bin/rails geonames:install` (also run from `bin/setup`) downloads `cities1000.zip`, `countryInfo.txt` and `admin1CodesASCII.txt` into `storage/geonames/` (gitignored). `GEONAMES_DATASET=cities500` (denser) or `cities15000` (smaller) swaps the dataset; `FORCE=1` redownloads.
- `ReverseGeocoder.lookup(lat, lng)` loads the files once per process and returns the nearest place within 50 km, labelled "Name, Region, Country".
- `GET /reverse_geocode?lat=..&lng=..` serves it to the location controller. With no data or no match it returns `label: null` and the field falls back to plain coordinates.

## Limits and upgrade path

- Linear scan is fine for ~150k rows. Switching to `allCountries` (~12M rows) would need a spatial index (k-d tree or SQLite R*Tree).
- Street-level accuracy would need a self-hosted Photon/Nominatim; revisit only if that is ever wanted.
- GeoNames is CC-BY 4.0: credit "GeoNames (geonames.org)" if the data is ever shown or redistributed publicly.
