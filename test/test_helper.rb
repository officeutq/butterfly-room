ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "nokogiri"

require "devise"
require "warden/test/helpers"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
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
