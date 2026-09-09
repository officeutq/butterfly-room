# frozen_string_literal: true

require "uri"

module Stores
  module AiAutofill
    # Only URLs supported by the same search's verified official evidence may
    # cross the boundary into server-side image fetching. Form URLs are not used.
    class ImageSources
      FIELDS = %w[website_url x_url instagram_url tiktok_url youtube_url].freeze
      LABELS = %w[公式サイト X Instagram TikTok YouTube].freeze
      PURPOSE = "store_registration_image"

      def self.from(fields:, evidence:)
        FIELDS.filter_map.with_index do |field, index|
          target = fields[field]
          kind = field == "website_url" ? "official_website" : "official_sns"
          next if target.blank?

          verified = evidence.find do |item|
            item["kind"] == kind && same_owner?(target, item["source_url"], field:)
          end
          next unless verified

          # Keep the verified branch page, rather than widening to a brand home.
          { "kind" => field, "title" => LABELS[index], "url" => verified.fetch("source_url") }
        end
      end

      def self.token_for(sources, store:, actor:)
        return if sources.empty?

        verifier.generate(
          { "store_id" => store.id, "user_id" => actor.id, "sources" => sources },
          purpose: PURPOSE, expires_in: 5.minutes
        )
      end

      def self.verify(token, store:, actor:)
        return if token.to_s.bytesize > 16.kilobytes

        data = verifier.verified(token.to_s, purpose: PURPOSE)
        return unless data.is_a?(Hash) && data["store_id"] == store.id && data["user_id"] == actor.id

        data["sources"]
      end

      def self.verifier
        Rails.application.message_verifier(PURPOSE)
      end

      def self.same_owner?(target, source, field:)
        left = page(target)
        right = page(source)
        return false unless left && right && left.host == right.host

        if field == "website_url"
          return false if SearchService::SOCIAL_HOSTS.values.flatten.include?(left.host)

          path = left.path.delete_suffix("/")
          right.path == path || right.path.start_with?("#{path}/")
        elsif field == "youtube_url"
          # Do not equate arbitrary videos or channels on youtube.com.
          left.path.delete_suffix("/") == right.path.delete_suffix("/") && left.query == right.query
        else
          account = left.path.split("/")[1]
          account.present? && account == right.path.split("/")[1] &&
            !%w[home explore search accounts login intent share i].include?(account.downcase)
        end
      end

      def self.page(value)
        uri = URI.parse(value.to_s)
        return unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil?
        return unless [ 80, 443 ].include?(uri.port)

        uri.host = uri.host.downcase.delete_prefix("www.")
        uri.host = "x.com" if uri.host == "twitter.com"
        uri
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
