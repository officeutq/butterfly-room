# frozen_string_literal: true

module LpAnalytics
  class Configuration
    STORE_LP_202607 = "stores_lp_202607"
    STORE_LP_202609 = "stores_lp_202609"

    CTA_DEFINITIONS = {
      "pc_sidebar_registration" => {
        name: "今すぐ始める",
        position: "PC左側",
        kind: :registration
      }.freeze,
      "hero_registration" => {
        name: "無料登録",
        position: "ファーストビュー",
        kind: :registration
      }.freeze,
      "flow_registration" => {
        name: "今すぐ始める",
        position: "FLOW付近",
        kind: :registration
      }.freeze,
      "bottom_registration" => {
        name: "店舗登録はこちら",
        position: "最下部",
        kind: :registration
      }.freeze,
      "bottom_contact" => {
        name: "お問い合わせはこちら",
        position: "最下部",
        kind: :contact
      }.freeze
    }.freeze
    REGISTRATION_CTA_KEYS = CTA_DEFINITIONS.filter_map do |key, definition|
      key if definition.fetch(:kind) == :registration
    end.freeze
    CONTACT_CTA_KEYS = CTA_DEFINITIONS.filter_map do |key, definition|
      key if definition.fetch(:kind) == :contact
    end.freeze

    SECTION_LABELS = {
      "USAGE" => "USAGE",
      "STRENGTHS" => "STRENGTHS",
      "SYSTEM" => "SYSTEM",
      "PRICING" => "PRICING",
      "FLOW" => "FLOW",
      "CAST" => "CAST",
      "QA" => "QA",
      "bottom_cta" => "最下部CTA"
    }.freeze

    STORE_LP_202609_CTA_DEFINITIONS = {
      "hero_registration" => {
        name: "店舗登録する",
        position: "ファーストビュー",
        kind: :registration
      }.freeze,
      "hero_contact" => {
        name: "問い合わせる",
        position: "ファーストビュー",
        kind: :contact
      }.freeze,
      "hero_faq" => {
        name: "店舗向けFAQを見る",
        position: "ファーストビュー",
        kind: :faq
      }.freeze,
      "header_registration" => {
        name: "店舗登録する",
        position: "PCヘッダー",
        kind: :registration
      }.freeze,
      "bottom_registration" => {
        name: "店舗登録する",
        position: "最下部",
        kind: :registration
      }.freeze,
      "bottom_contact" => {
        name: "問い合わせる",
        position: "最下部",
        kind: :contact
      }.freeze,
      "bottom_faq" => {
        name: "店舗向けFAQを見る",
        position: "最下部",
        kind: :faq
      }.freeze,
      "mobile_registration" => {
        name: "店舗登録する",
        position: "スマートフォン固定導線",
        kind: :registration
      }.freeze
    }.freeze

    STORE_LP_202609_SECTION_LABELS = {
      "existing_customer_opportunity" => "問題提起・既存客の機会",
      "service_introduction" => "Butterflyveの紹介",
      "usage_mechanism" => "利用の仕組み",
      "service_comparison" => "一般的な配信との違い",
      "adoption_cost" => "導入ハードル・料金",
      "usage_scenes" => "活用シーン",
      "getting_started" => "始め方",
      "final_opportunity_cta" => "新しい売上の機会・最下部CTA"
    }.freeze

    LP_DEFINITIONS = {
      STORE_LP_202607 => {
        sections: SECTION_LABELS.keys.freeze,
        ctas: CTA_DEFINITIONS.keys.freeze,
        faqs: %w[faq_1 faq_2 faq_3 faq_4].freeze,
        section_labels: SECTION_LABELS,
        cta_definitions: CTA_DEFINITIONS,
        bottom_section: "bottom_cta"
      }.freeze,
      STORE_LP_202609 => {
        sections: STORE_LP_202609_SECTION_LABELS.keys.freeze,
        ctas: STORE_LP_202609_CTA_DEFINITIONS.keys.freeze,
        faqs: [].freeze,
        section_labels: STORE_LP_202609_SECTION_LABELS,
        cta_definitions: STORE_LP_202609_CTA_DEFINITIONS,
        bottom_section: "final_opportunity_cta"
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

      def definition_for(lp_identifier)
        LP_DEFINITIONS.fetch(lp_identifier)
      end

      def section_labels_for(lp_identifier)
        definition_for(lp_identifier).fetch(:section_labels)
      end

      def cta_definitions_for(lp_identifier)
        definition_for(lp_identifier).fetch(:cta_definitions)
      end

      def cta_keys_for(lp_identifier, kind:)
        cta_definitions_for(lp_identifier).filter_map do |key, definition|
          key if definition.fetch(:kind) == kind
        end
      end

      def bottom_section_for(lp_identifier)
        definition_for(lp_identifier).fetch(:bottom_section)
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
