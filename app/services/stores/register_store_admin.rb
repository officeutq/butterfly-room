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
  end
end
