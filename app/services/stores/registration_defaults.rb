# frozen_string_literal: true

module Stores
  class RegistrationDefaults
    DEFAULT_REFERRAL_CODE = "0000"

    class << self
      def normalized_referral_code(value)
        value.to_s.strip.presence || DEFAULT_REFERRAL_CODE
      end

      def usable_referral_code(value)
        referral_code = ReferralCode.find_by(code: normalized_referral_code(value))
        referral_code if referral_code&.usable?
      end

      def usable_referral_code!(value)
        referral_code = ReferralCode.find_by!(code: normalized_referral_code(value))
        return referral_code if referral_code.usable?

        referral_code.errors.add(:code, :invalid)
        raise ActiveRecord::RecordInvalid, referral_code
      end

      def create_default_drink_items!(store)
        default_drink_item_attributes.each do |attributes|
          store.drink_items.create!(
            name: attributes.fetch("name"),
            price_points: attributes.fetch("price_points"),
            position: attributes.fetch("position"),
            enabled: attributes.fetch("enabled"),
            icon_key: attributes["icon_key"]
          )
        end
      end

      def default_drink_item_attributes
        YAML.safe_load(
          File.read(Rails.root.join("config/default_drink_items.yml")),
          aliases: true
        ).fetch(Rails.env).fetch("items")
      end
    end
  end
end
