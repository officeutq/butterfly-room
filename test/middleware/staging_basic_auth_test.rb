# frozen_string_literal: true

require "test_helper"

class StagingBasicAuthTest < ActiveSupport::TestCase
  APP = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
  STAGING_ENV = {
    "APP_ENV" => "staging",
    "BASIC_AUTH_ENABLED" => "true",
    "BASIC_AUTH_USERNAME" => "tester",
    "BASIC_AUTH_PASSWORD" => "secret"
  }.freeze

  test "requires credentials in staging" do
    response = middleware.call(Rack::MockRequest.env_for("/"))

    assert_equal 401, response.first
  end

  test "accepts matching credentials" do
    request_env = Rack::MockRequest.env_for("/")
    request_env["HTTP_AUTHORIZATION"] = ActionController::HttpAuthentication::Basic.encode_credentials("tester", "secret")

    assert_equal 200, middleware.call(request_env).first
  end

  test "allows health and robots endpoints without credentials" do
    assert_equal 200, middleware.call(Rack::MockRequest.env_for("/up")).first
    assert_equal 200, middleware.call(Rack::MockRequest.env_for("/robots.txt")).first
  end

  private

  def middleware
    Staging::BasicAuth.new(APP, env: STAGING_ENV)
  end
end
