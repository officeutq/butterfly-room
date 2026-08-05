# frozen_string_literal: true

module Stores
  class RegisterProxyStore
    class NotAuthorized < StandardError; end

    Result = Struct.new(:store, :membership, keyword_init: true)

    def self.call!(store_name:, referral_code:, actor:)
      new(store_name:, referral_code:, actor:).call!
    end

    def initialize(store_name:, referral_code:, actor:)
      @store_name = store_name
      @referral_code = referral_code
      @actor = actor
    end

    def call!
      authorize_actor!
      referral_code = RegistrationDefaults.usable_referral_code!(@referral_code)
      store = nil
      membership = nil

      ActiveRecord::Base.transaction do
        store = Store.create!(
          name: @store_name,
          referral_code: referral_code,
          published: false,
          onboarding_step: :invite_cast
        )

        RegistrationDefaults.create_default_drink_items!(store)

        membership = StoreMembership.create!(
          store: store,
          user: @actor,
          membership_role: :admin
        )
      end

      Result.new(store: store, membership: membership)
    end

    private

    def authorize_actor!
      allowed = @actor&.store_admin? && @actor.permitted_for?(:store_registration_proxy)
      raise NotAuthorized unless allowed
    end
  end
end
