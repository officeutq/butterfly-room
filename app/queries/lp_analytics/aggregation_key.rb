# frozen_string_literal: true

require "digest"
require "json"

module LpAnalytics
  class AggregationKey
    DIMENSIONS = %i[
      aggregation_date
      lp_identifier
      traffic_source
      utm_source
      utm_medium
      utm_campaign
      utm_content
    ].freeze

    class << self
      def generate(**dimensions)
        canonical = DIMENSIONS.to_h do |dimension|
          value = dimensions.fetch(dimension)
          value = value.iso8601 if value.respond_to?(:iso8601)
          [ dimension.to_s, value.to_s ]
        end

        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end
    end
  end
end
