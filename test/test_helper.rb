ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "nokogiri"

require "devise"
require "warden/test/helpers"

# Rails 8 ではルートが遅延ロードされるため、Devise の Warden 設定を先に初期化する。
Rails.application.routes_reloader.execute_unless_loaded

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    def with_env(values)
      previous = values.keys.to_h { |key| [ key, ENV[key] ] }

      values.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end

      yield
    ensure
      previous.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end
end

class ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include Devise::Test::IntegrationHelpers

  def data_layer_events
    Nokogiri::HTML(response.body).css("script").filter_map do |script|
      match = script.text.match(/window\.dataLayer\.push\((\{.*\})\);/m)
      JSON.parse(match[1]) if match
    end
  end

  teardown do
    Warden.test_reset!
  end
end
