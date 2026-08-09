# frozen_string_literal: true

module LpAnalytics
  class Configuration
    STORE_LP_202607 = "stores_lp_202607"

    LP_DEFINITIONS = {
      STORE_LP_202607 => {
        sections: %w[USAGE STRENGTHS SYSTEM PRICING FLOW CAST QA bottom_cta].freeze,
        ctas: %w[
          pc_sidebar_registration
          hero_registration
          flow_registration
          bottom_registration
          bottom_contact
        ].freeze,
        faqs: %w[faq_1 faq_2 faq_3 faq_4].freeze
      }.freeze
    }.freeze

    VALUELESS_EVENT_TYPES = %w[
      lp_view
      store_registration_form_view
      store_registration_complete
      store_contact_form_view
      store_contact_complete
    ].freeze
    SCROLL_VALUES = %w[25 50 75 90].freeze
    VIEWPORT_TYPES = %w[pc smartphone tablet].freeze
    METADATA_KEYS = %w[viewport_type].freeze

    class << self
      def supported_lp?(lp_identifier)
        LP_DEFINITIONS.key?(lp_identifier)
      end

      def allowed_event_value?(lp_identifier:, event_type:, event_value:)
        definition = LP_DEFINITIONS[lp_identifier]
        return false unless definition

        case event_type
        when *VALUELESS_EVENT_TYPES
          event_value.nil?
        when "scroll_reached"
          SCROLL_VALUES.include?(event_value)
        when "section_reached"
          definition.fetch(:sections).include?(event_value)
        when "cta_reached", "cta_clicked"
          definition.fetch(:ctas).include?(event_value)
        when "faq_opened"
          definition.fetch(:faqs).include?(event_value)
        else
          false
        end
      end

      def valid_metadata?(metadata)
        return false unless metadata.is_a?(Hash)
        return false unless metadata.keys.all? { |key| METADATA_KEYS.include?(key.to_s) }

        metadata.all? do |key, value|
          case key.to_s
          when "viewport_type"
            value.is_a?(String) && VIEWPORT_TYPES.include?(value)
          else
            false
          end
        end
      end
    end
  end
end
