# frozen_string_literal: true

module LpAnalytics
  module Visits
    class ResolveService
      INACTIVITY_TIMEOUT = 30.minutes
      TRAFFIC_KEYS = %i[
        traffic_source
        utm_source
        utm_medium
        utm_campaign
        utm_content
        referral_code
      ].freeze

      def initialize(
        public_id:,
        lp_identifier:,
        traffic_attributes:,
        user_agent:,
        preserve_existing_traffic: false,
        configuration: Configuration,
        now: Time.current
      )
        @public_id = public_id.to_s.strip.presence
        @lp_identifier = lp_identifier.to_s.strip
        @traffic_attributes = normalize_traffic_attributes(traffic_attributes)
        @client = ClientClassifier.call(user_agent)
        @preserve_existing_traffic = preserve_existing_traffic
        @configuration = configuration
        @now = now
      end

      def call
        raise ArgumentError, "unsupported LP identifier" unless @configuration.supported_lp?(@lp_identifier)

        current_visit = Visit.find_by_public_id(@public_id)
        expected_traffic = preserved_or_current_traffic(current_visit)

        if reusable?(current_visit, expected_traffic)
          current_visit.update!(
            last_activity_at: @now,
            device_type: @client.device_type,
            browser_type: @client.browser_type
          )
          return current_visit
        end

        Visit.create!(
          lp_identifier: @lp_identifier,
          **expected_traffic,
          device_type: @client.device_type,
          browser_type: @client.browser_type,
          started_at: @now,
          last_activity_at: @now
        )
      end

      private

      def normalize_traffic_attributes(attributes)
        source = attributes.respond_to?(:to_h) ? attributes.to_h : {}

        TRAFFIC_KEYS.to_h do |key|
          raw_value = source[key] || source[key.to_s]
          normalized = raw_value.is_a?(String) ? raw_value.strip.presence : nil
          [ key, normalized&.slice(0, Visit::TRAFFIC_VALUE_MAX_LENGTH) ]
        end
      end

      def preserved_or_current_traffic(current_visit)
        if @preserve_existing_traffic && current_visit&.lp_identifier == @lp_identifier
          current_visit.traffic_attributes
        else
          @traffic_attributes
        end
      end

      def reusable?(visit, expected_traffic)
        return false unless visit
        return false unless visit.lp_identifier == @lp_identifier
        return false unless visit.last_activity_at > @now - INACTIVITY_TIMEOUT

        visit.traffic_attributes == expected_traffic
      end
    end
  end
end
