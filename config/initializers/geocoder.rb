app_name =
  if Rails.env.production?
    "Butterflyve"
  else
    "Butterflyve development"
  end

Geocoder.configure(
  lookup: :nominatim,
  use_https: true,
  timeout: 5,
  units: :km,
  http_headers: {
    "User-Agent" => "#{app_name} (contact: info@officeutq.co.jp)"
  }
)
