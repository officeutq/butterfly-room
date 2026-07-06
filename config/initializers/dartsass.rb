Rails.application.configure do
  # ビルド定義（既にあればそのままでOK）
  config.dartsass.builds = {
    "application.scss" => "app/assets/builds/application.css",
    "store_lp_202607.scss" => "app/assets/builds/store_lp_202607.css"
  }
end
