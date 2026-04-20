Geocoder.configure(
  lookup: :google,
  api_key: ENV["GOOGLE_MAPS_API_KEY"],
  use_https: true,
  timeout: 5,
  units: :km
)
