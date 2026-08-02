# frozen_string_literal: true

require "test_helper"

class StagingRobotsTest < ActiveSupport::TestCase
  APP = ->(_env) { [ 200, { "content-type" => "text/html" }, [ "ok" ] ] }

  test "runs before static file serving" do
    middleware_classes = Rails.application.middleware.map(&:klass)
    robots_index = middleware_classes.index(Staging::Robots)
    static_index = middleware_classes.index(ActionDispatch::Static)

    assert robots_index, "Staging::Robots is not registered"
    assert static_index, "ActionDispatch::Static is not registered"
    assert_operator robots_index, :<, static_index
  end

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
