# frozen_string_literal: true

require "digest"

module Staging
  class BasicAuth
    EXCLUDED_PATHS = %w[/up /robots.txt /webhooks/stripe].freeze

    def initialize(app, env: ENV)
      @app = app
      @env = env
    end

    def call(request_env)
      return @app.call(request_env) unless Runtime.staging?(@env)
      return @app.call(request_env) unless Runtime.enabled?("BASIC_AUTH_ENABLED", default: true, env: @env)
      return @app.call(request_env) if EXCLUDED_PATHS.include?(request_env["PATH_INFO"])

      request = Rack::Auth::Basic::Request.new(request_env)
      return unauthorized unless request.provided? && request.basic? && valid_credentials?(request.credentials)

      @app.call(request_env)
    end

    private

    def valid_credentials?(credentials)
      username, password = credentials
      expected_username = @env["BASIC_AUTH_USERNAME"].to_s
      expected_password = @env["BASIC_AUTH_PASSWORD"].to_s
      return false if expected_username.empty? || expected_password.empty?

      secure_compare(username, expected_username) && secure_compare(password, expected_password)
    end

    def secure_compare(actual, expected)
      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(actual.to_s),
        Digest::SHA256.hexdigest(expected.to_s)
      )
    end

    def unauthorized
      [
        401,
        {
          "content-type" => "text/plain; charset=utf-8",
          "www-authenticate" => 'Basic realm="Butterfly Room Staging"',
          "x-robots-tag" => "noindex, nofollow"
        },
        [ "Authentication required" ]
      ]
    end
  end
end
