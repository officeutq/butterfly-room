ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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

  teardown do
    Warden.test_reset!
  end
end
