# frozen_string_literal: true

module Casts
  class RegistrationForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :email, :string
    attribute :password, :string
    attribute :password_confirmation, :string

    attr_reader :user

    validates :email, presence: true
    validates :password, presence: true, confirmation: true
    validates :password_confirmation, presence: true
    validate  :email_must_be_unique

    def save
      return false unless valid?

      result = Casts::RegisterCast.call!(
        email: email,
        password: password
      )

      @user = result.user
      true
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.each do |error|
        errors.add(error.attribute, error.type, **error.options.except(:message))
      end
      false
    end

    private

    def email_must_be_unique
      return if email.blank?
      return unless User.exists?(email: email)

      errors.add(:email, :taken)
    end
  end
end
