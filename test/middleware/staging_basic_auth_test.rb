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

  test "allows the Stripe webhook endpoint without credentials" do
    request_env = Rack::MockRequest.env_for("/webhooks/stripe", method: "POST")

    assert_equal 200, middleware.call(request_env).first
  end

  test "requires credentials for paths similar to the Stripe webhook endpoint" do
    request_env = Rack::MockRequest.env_for("/webhooks/stripe-test", method: "POST")

    assert_equal 401, middleware.call(request_env).first
  end

  test "does not require credentials outside staging" do
    env = STAGING_ENV.merge("APP_ENV" => "production")
    production_middleware = Staging::BasicAuth.new(APP, env: env)

    assert_equal 200, production_middleware.call(Rack::MockRequest.env_for("/")).first
  end

  test "does not require credentials when disabled in staging" do
    env = STAGING_ENV.merge(
      "BASIC_AUTH_ENABLED" => "false",
      "BASIC_AUTH_USERNAME" => "",
      "BASIC_AUTH_PASSWORD" => ""
    )
    public_middleware = Staging::BasicAuth.new(APP, env: env)

    assert_equal 200, public_middleware.call(Rack::MockRequest.env_for("/")).first
  end

  private

  def middleware
    Staging::BasicAuth.new(APP, env: STAGING_ENV)
  end
end
