# frozen_string_literal: true

require "test_helper"

class StagingRobotsTest < ActiveSupport::TestCase
  APP = ->(_env) { [ 200, { "content-type" => "text/html" }, [ "ok" ] ] }

  test "blocks crawling and adds a noindex response header in staging" do
    middleware = Staging::Robots.new(APP, env: { "APP_ENV" => "staging" })

    robots_response = middleware.call(Rack::MockRequest.env_for("/robots.txt"))
    page_response = middleware.call(Rack::MockRequest.env_for("/page"))

    assert_equal "User-agent: *\nDisallow: /\n", robots_response.last.join
    assert_equal "noindex, nofollow", robots_response.second["x-robots-tag"]
    assert_equal "noindex, nofollow", page_response.second["x-robots-tag"]
  end

  test "does not alter production responses" do
    middleware = Staging::Robots.new(APP, env: { "APP_ENV" => "production" })
    response = middleware.call(Rack::MockRequest.env_for("/page"))

    assert_nil response.second["x-robots-tag"]
  end
end
