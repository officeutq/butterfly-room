Rails.application.configure do
  # ビルド定義（既にあればそのままでOK）
  config.dartsass.builds = {
    "application.scss" => "app/assets/builds/application.css"
  }
end
