# frozen_string_literal: true

module Stores
  class RegisterStoreAdmin
    DEFAULT_REFERRAL_CODE = RegistrationDefaults::DEFAULT_REFERRAL_CODE

    Result = Struct.new(:store, :user, keyword_init: true)

    def self.call!(store_name:, email:, password:, referral_code:, lp_analytics_visit: nil)
      new(store_name:, email:, password:, referral_code:, lp_analytics_visit:).call!
    end

    def initialize(store_name:, email:, password:, referral_code:, lp_analytics_visit: nil)
      @store_name = store_name
      @email = email
      @password = password
      @referral_code = RegistrationDefaults.normalized_referral_code(referral_code)
      @lp_analytics_visit = lp_analytics_visit
    end

    def call!
      rc = RegistrationDefaults.usable_referral_code!(@referral_code)

      store = nil
      user = nil

      ActiveRecord::Base.transaction do
        store = Store.create!(
          name: @store_name,
          referral_code: rc,
          lp_analytics_visit: @lp_analytics_visit,
          published: false,
          onboarding_step: :invite_cast
        )

        RegistrationDefaults.create_default_drink_items!(store)

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

      record_lp_analytics_completion(store)
      Result.new(store: store, user: user)
    end

    private

    def record_lp_analytics_completion(store)
      return if @lp_analytics_visit.blank?

      LpAnalytics::Completions::RecordService.new(
        visit: @lp_analytics_visit,
        event_type: "store_registration_complete",
        completion_record: store
      ).call
    end
  end
end
