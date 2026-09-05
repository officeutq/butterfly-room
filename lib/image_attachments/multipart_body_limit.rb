# frozen_string_literal: true

require "json"

module ImageAttachments
  # Rejects oversized multipart requests before Action Dispatch parses their
  # parameters. The counting input also covers missing or false Content-Length
  # values in Rack environments where Puma's parser is not the entry point.
  class MultipartBodyLimit
    class RequestTooLarge < StandardError; end

    MULTIPART_CONTENT_TYPE = %r{\Amultipart/form-data(?:;|\z)}i

    def initialize(app, limit: MultipartLimits::MAX_REQUEST_BYTES)
      @app = app
      @limit = Integer(limit)
    end

    def call(env)
      return @app.call(env) unless multipart_request?(env)
      return too_large_response if declared_length(env) > @limit

      original_input = env.fetch("rack.input")
      env["rack.input"] = LimitedInput.new(original_input, limit: @limit)
      @app.call(env)
    rescue RequestTooLarge
      too_large_response
    ensure
      env["rack.input"] = original_input if defined?(original_input) && original_input
    end

    private

    def multipart_request?(env)
      env.fetch("CONTENT_TYPE", "").match?(MULTIPART_CONTENT_TYPE)
    end

    def declared_length(env)
      value = env["CONTENT_LENGTH"]
      return 0 if value.nil? || value.empty?

      length = Integer(value, 10)
      length.negative? ? 0 : length
    rescue ArgumentError, TypeError
      0
    end

    def too_large_response
      body = JSON.generate(
        error: "image_pair_request_too_large",
        message: "画像を含むリクエストは26MiB以下にしてください。再度保存してください。",
        max_bytes: @limit,
        retryable: true
      )
      [
        413,
        {
          "Content-Type" => "application/json; charset=utf-8",
          "Content-Length" => body.bytesize.to_s,
          "Cache-Control" => "no-store"
        },
        [ body ]
      ]
    end

    class LimitedInput
      def initialize(input, limit:)
        @input = input
        @limit = limit
        @bytes_read = 0
      end

      def read(*args)
        count!(@input.read(*args))
      end

      def gets(*args)
        count!(@input.gets(*args))
      end

      def each(*args)
        return enum_for(__method__, *args) unless block_given?

        while (line = gets(*args))
          yield line
        end
      end

      def readpartial(*args)
        count!(@input.readpartial(*args))
      end

      def sysread(*args)
        count!(@input.sysread(*args))
      end

      def read_nonblock(*args, **kwargs)
        count!(@input.read_nonblock(*args, **kwargs))
      end

      def rewind
        @input.rewind.tap { @bytes_read = 0 }
      end

      def method_missing(name, ...)
        @input.public_send(name, ...)
      end

      def respond_to_missing?(name, include_private = false)
        @input.respond_to?(name, include_private) || super
      end

      private

      def count!(value)
        return value unless value.is_a?(String)

        @bytes_read += value.bytesize
        raise RequestTooLarge if @bytes_read > @limit

        value
      end
    end
  end
end
