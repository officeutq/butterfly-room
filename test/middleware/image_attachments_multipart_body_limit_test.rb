# frozen_string_literal: true

require "test_helper"

class ImageAttachments::MultipartBodyLimitTest < ActiveSupport::TestCase
  test "is the first application middleware before parameter parsing" do
    middleware_classes = Rails.application.middleware.map(&:klass)

    assert_equal ImageAttachments::MultipartBodyLimit, middleware_classes.first
  end

  test "rejects an oversized declared multipart body without calling the application" do
    called = false
    app = lambda do |_env|
      called = true
      [ 200, {}, [ "ok" ] ]
    end
    env = multipart_env("small", content_length: 11)

    response = described_class.new(app, limit: 10).call(env)

    assert_equal 413, response.first
    assert_not called
    assert_equal "no-store", response.second.fetch("Cache-Control")
    assert_equal true, JSON.parse(response.last.join).fetch("retryable")
  end

  test "counts the body when Content-Length is missing or falsely small" do
    app = lambda do |env|
      env.fetch("rack.input").read
      [ 200, {}, [ "ok" ] ]
    end

    [ nil, 3 ].each do |content_length|
      response = described_class.new(app, limit: 10).call(
        multipart_env("12345678901", content_length:)
      )

      assert_equal 413, response.first
    end
  end

  test "allows the exact boundary and restores rack input" do
    original = StringIO.new("1234567890")
    env = multipart_env(original, content_length: 10)
    app = lambda do |request_env|
      assert_not_same original, request_env.fetch("rack.input")
      assert_equal "1234567890", request_env.fetch("rack.input").read
      [ 204, {}, [] ]
    end

    response = described_class.new(app, limit: 10).call(env)

    assert_equal 204, response.first
    assert_same original, env.fetch("rack.input")
  end

  test "does not apply the Rails multipart guard to normal JSON requests" do
    app = ->(_env) { [ 204, {}, [] ] }
    env = Rack::MockRequest.env_for(
      "/normal",
      method: "POST",
      input: "{}",
      "CONTENT_TYPE" => "application/json",
      "CONTENT_LENGTH" => "999"
    )

    assert_equal 204, described_class.new(app, limit: 10).call(env).first
  end

  private

  def described_class
    ImageAttachments::MultipartBodyLimit
  end

  def multipart_env(input, content_length:)
    input = StringIO.new(input) if input.is_a?(String)
    Rack::MockRequest.env_for(
      "/image-pair",
      method: "POST",
      input:,
      "CONTENT_TYPE" => "multipart/form-data; boundary=test-boundary"
    ).tap do |env|
      content_length.nil? ? env.delete("CONTENT_LENGTH") : env["CONTENT_LENGTH"] = content_length.to_s
    end
  end
end
