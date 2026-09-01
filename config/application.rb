require_relative "boot"

require "rails/all"

require_relative "../lib/staging/basic_auth"
require_relative "../lib/staging/robots"

Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    config.load_defaults 8.1

    config.i18n.default_locale = :ja
    config.x.beauty_provider = ENV.fetch("BEAUTY_PROVIDER", "banuba")
    config.active_storage.variant_processor = :mini_magick

    # Propshaft の assets load path を早い段階で確定（testでも効かせる）
    config.assets.paths << Rails.root.join("app/assets/builds")
    config.assets.paths << Rails.root.join("node_modules")
    config.assets.paths << Rails.root.join("vendor/assets")
    config.assets.paths << Rails.root.join("vendor/assets/stylesheets")

    config.autoload_lib(ignore: %w[assets tasks])

    config.middleware.insert_before ActionDispatch::Static, Staging::Robots
    config.middleware.use Staging::BasicAuth
  end
end
