# frozen_string_literal: true

module Staging
  class Robots
    ROBOTS_BODY = "User-agent: *\nDisallow: /\n"

    def initialize(app, env: ENV)
      @app = app
      @env = env
    end

    def call(request_env)
      return @app.call(request_env) unless Runtime.staging?(@env)

      if request_env["PATH_INFO"] == "/robots.txt"
        return [ 200, { "content-type" => "text/plain; charset=utf-8", "x-robots-tag" => "noindex, nofollow" }, [ ROBOTS_BODY ] ]
      end

      status, headers, body = @app.call(request_env)
      headers["x-robots-tag"] = "noindex, nofollow"
      [ status, headers, body ]
    end
  end
end
