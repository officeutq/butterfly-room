# frozen_string_literal: true

module Stores
  class ProxyRegistrationForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :store_name, :string
    attribute :referral_code, :string

    attr_accessor :actor
    attr_reader :store

    validates :store_name, presence: true
    validate :referral_code_must_be_usable

    def save
      return false unless valid?

      result = Stores::RegisterProxyStore.call!(
        store_name: store_name,
        referral_code: referral_code,
        actor: actor
      )
      @store = result.store
      true
    rescue Stores::RegisterProxyStore::NotAuthorized
      errors.add(:base, "代行対象店舗を作成する権限がありません")
      false
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.each do |error|
        attribute = error.attribute == :code ? :referral_code : error.attribute
        errors.add(attribute, error.type, **error.options.except(:message))
      end
      false
    end

    private

    def referral_code_must_be_usable
      return if Stores::RegistrationDefaults.usable_referral_code(referral_code).present?

      errors.add(:referral_code, :invalid)
    end
  end
end
