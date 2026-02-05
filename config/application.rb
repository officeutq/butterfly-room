require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    config.load_defaults 8.1

    # Propshaft の assets load path を早い段階で確定（testでも効かせる）
    config.assets.paths << Rails.root.join("app/assets/builds")
    config.assets.paths << Rails.root.join("node_modules")
    config.assets.paths << Rails.root.join("vendor/assets")
    config.assets.paths << Rails.root.join("vendor/assets/stylesheets")

    config.autoload_lib(ignore: %w[assets tasks])
  end
end
