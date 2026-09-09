# frozen_string_literal: true

require "mini_magick"
require "nokogiri"
require "tempfile"

module Stores
  module AiAutofill
    class ImageImportService
      class InvalidToken < StandardError; end
      Result = Data.define(:bytes, :content_type, :source)
      TOTAL_SECONDS = 15
      SOURCE_SECONDS = 3
      MAX_IMAGE_BYTES = 5.megabytes
      CONTENT_TYPES = { "JPEG" => "image/jpeg", "PNG" => "image/png", "WEBP" => "image/webp" }.freeze

      attr_reader :attempts

      def initialize(store:, actor:, token:, fetcher: PublicImageFetcher.new)
        @sources = ImageSources.verify(token, store:, actor:)
        @fetcher = fetcher
        @attempts = []
      end

      def call
        raise InvalidToken unless @sources.is_a?(Array)

        deadline = now + TOTAL_SECONDS
        @sources.first(5).each do |source|
          break if now >= deadline

          result = import_source(source, deadline: [ deadline, now + SOURCE_SECONDS ].min)
          return result if result
        end
        nil
      end

      private

      def import_source(source, deadline:)
        page = @fetcher.call(source.fetch("url"), max_bytes: 1.megabyte, deadline:,
          allowed_redirect: ->(url) { same_page?(source.fetch("url"), url) })
        raise PublicImageFetcher::Error, "not_html" unless %w[text/html application/xhtml+xml].include?(page.content_type)

        urls = image_urls(page, source:)
        urls.each do |url|
          begin
            image = @fetcher.call(url, max_bytes: MAX_IMAGE_BYTES, deadline:)
            content_type = inspect_image(image.body, deadline:)
            @attempts << { kind: source.fetch("kind"), status: "found" }
            return Result.new(bytes: image.body, content_type:, source: source.merge("url" => page.url))
          rescue PublicImageFetcher::Error => error
            @attempts << { kind: source.fetch("kind"), status: error.message }
          end
        end
        @attempts << { kind: source.fetch("kind"), status: "no_image" } if urls.empty?
        nil
      rescue PublicImageFetcher::Error => error
        @attempts << { kind: source.fetch("kind"), status: error.message }
        nil
      end

      def same_page?(original, redirected)
        left = ImageSources.page(original)
        right = ImageSources.page(redirected)
        left && right && left.host == right.host &&
          left.path.delete_suffix("/") == right.path.delete_suffix("/") && left.query == right.query
      end

      def image_urls(page, source:)
        document = Nokogiri::HTML(page.body)
        if source.fetch("kind") != "website_url"
          canonical = document.at_css("meta[property='og:url']")&.[]("content") ||
            document.at_css("link[rel='canonical']")&.[]("href")
          unless ImageSources.same_owner?(page.url, canonical, field: source.fetch("kind"))
            raise PublicImageFetcher::Error, "page_identity_missing"
          end
        end
        # Trial policy: the page author's representative image, then Twitter Card.
        # No arbitrary <img>, latest post crawling, login bypass or video download.
        %w[og:image twitter:image].flat_map do |property|
          document.css("meta[property='#{property}'], meta[name='#{property}']").filter_map do |meta|
            value = meta["content"].to_s.strip
            URI.join(page.url, value).to_s if value.present?
          rescue URI::Error
            nil
          end
        end.uniq.first(2)
      end

      def inspect_image(bytes, deadline:)
        format = if bytes.start_with?("\xff\xd8".b)
          "JPEG"
        elsif bytes.start_with?("\x89PNG\r\n\x1a\n".b)
          "PNG"
        elsif bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP"
          "WEBP"
        end
        raise PublicImageFetcher::Error, "unsupported_image" unless format

        Tempfile.create([ "store-image-candidate", ".#{format.downcase}" ]) do |file|
          file.binmode
          file.write(bytes)
          file.flush
          header = identify(file.path, format:, deadline:, decode: false)
          image_format, width, height, count = header.split
          width = width.to_i
          height = height.to_i
          unless image_format == format && count == "1" && width >= 320 && height >= 168 &&
              width <= 8192 && height <= 8192 && width * height <= 32_000_000 &&
              [ width.fdiv(height), height.fdiv(width) ].max <= 8
            raise PublicImageFetcher::Error, "invalid_dimensions"
          end
          raise PublicImageFetcher::Error, "invalid_image" unless identify(file.path, format:, deadline:, decode: true) == header
        end
        CONTENT_TYPES.fetch(format)
      rescue MiniMagick::Error, MiniMagick::Invalid
        raise PublicImageFetcher::Error, "invalid_image"
      end

      def identify(path, format:, deadline:, decode:)
        remaining = [ deadline - now, 2 ].min
        raise PublicImageFetcher::Error, "timeout" unless remaining.positive?

        MiniMagick.public_send(decode ? :convert : :identify, timeout: remaining) do |command|
          command.limit("memory", "128MiB")
          command.limit("map", "128MiB")
          command.limit("disk", "0")
          command.limit("thread", "1")
          command.regard_warnings
          command.ping unless decode
          command.format("%m %w %h %n")
          command << "#{format}:#{path}"
          command << "info:" if decode
        end
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
