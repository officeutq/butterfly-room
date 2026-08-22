# frozen_string_literal: true

module Stores
  class MetaDescriptionBuilder
    MAX_LENGTH = 160
    BRAND_NAME = "Butterflyve（バタフライブ）"
    CLOSING_TEXT = "Butterflyveで店舗情報と公開中のブースを確認できます。"

    def self.call(store)
      new(store).call
    end

    def initialize(store)
      @store = store
    end

    def call
      text =
        if store_details?
          [ store_summary, business_hours, store_description, CLOSING_TEXT ].compact.join
        else
          "#{@store.name}の店舗情報と公開中のブースを#{BRAND_NAME}で確認できます。"
        end

      text.truncate(MAX_LENGTH, omission: "…")
    end

    private

    def store_details?
      [ @store.area, @store.business_type, @store.business_hours, @store.description ].any?(&:present?)
    end

    def store_summary
      area = @store.area.presence
      business_type = Store::BUSINESS_TYPE_LABELS[@store.business_type&.to_sym]

      if area && business_type
        "#{@store.name}は#{area}の#{business_type}です。"
      elsif area
        "#{@store.name}は#{area}の店舗です。"
      elsif business_type
        "#{@store.name}は#{business_type}です。"
      else
        "#{@store.name}の店舗情報です。"
      end
    end

    def business_hours
      value = @store.business_hours.presence
      "営業時間は#{sentence(value)}" if value
    end

    def store_description
      value = @store.description.to_s.squish.presence
      sentence(value) if value
    end

    def sentence(value)
      value.match?(/[。.!?！？]\z/) ? value : "#{value}。"
    end
  end
end
