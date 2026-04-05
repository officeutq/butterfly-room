# frozen_string_literal: true

module Stores
  class RegisterStoreAdmin
    Result = Struct.new(:store, :user, keyword_init: true)

    def self.call!(store_name:, email:, password:, referral_code:)
      new(store_name:, email:, password:, referral_code:).call!
    end

    def initialize(store_name:, email:, password:, referral_code:)
      @store_name = store_name
      @email = email
      @password = password
      @referral_code = referral_code
    end

    def call!
      rc = ReferralCode.find_by!(code: @referral_code)
      raise ActiveRecord::RecordInvalid.new(rc) unless rc.usable?

      store = nil
      user = nil

      ActiveRecord::Base.transaction do
        store = Store.create!(
          name: @store_name,
          referral_code: rc
        )

        create_default_drink_items!(store)

        user = User.create!(
          email: @email,
          password: @password,
          password_confirmation: @password,
          role: :store_admin
        )

        StoreMembership.create!(
          store: store,
          user: user,
          membership_role: :admin
        )
      end

      Result.new(store: store, user: user)
    end

    private

    def create_default_drink_items!(store)
      load_default_drink_items_attributes.each do |attrs|
        store.drink_items.create!(
          name: attrs.fetch("name"),
          price_points: attrs.fetch("price_points"),
          position: attrs.fetch("position"),
          enabled: attrs.fetch("enabled"),
          icon_key: attrs["icon_key"]
        )
      end
    end

    def load_default_drink_items_attributes
      YAML.safe_load(
        File.read(Rails.root.join("config/default_drink_items.yml")),
        aliases: true
      ).fetch(Rails.env).fetch("items")
    end
  end
end
