# frozen_string_literal: true

module Stores
  class RegistrationForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :store_name, :string
    attribute :email, :string
    attribute :password, :string
    attribute :password_confirmation, :string
    attribute :referral_code, :string

    attr_reader :user, :store

    validates :store_name, presence: true
    validates :email, presence: true
    validates :password, presence: true, confirmation: true
    validates :password_confirmation, presence: true
    validates :referral_code, presence: true
    validate  :referral_code_must_be_usable
    validate  :email_must_be_unique

    def save
      return false unless valid?

      result = Stores::RegisterStoreAdmin.call!(
        store_name: store_name,
        email: email,
        password: password,
        referral_code: referral_code
      )

      @store = result.store
      @user  = result.user
      true
    rescue ActiveRecord::RecordInvalid => e
      errors.add(:base, e.record.errors.full_messages.join(", "))
      false
    end

    private

    def referral_code_must_be_usable
      rc = ReferralCode.find_by(code: referral_code)
      if rc.nil? || !rc.usable?
        errors.add(:referral_code, "が無効です")
      end
    end

    def email_must_be_unique
      return if email.blank?

      if User.exists?(email: email)
        errors.add(:email, "このemailアドレスはすでに使われています")
      end
    end
  end
end
