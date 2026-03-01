# frozen_string_literal: true

module StoreAdmins
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

      result = StoreAdmins::RegisterStoreAdmin.call!(
        email: email,
        password: password
      )

      @user = result.user
      true
    rescue ActiveRecord::RecordInvalid => e
      errors.add(:base, e.record.errors.full_messages.join(", "))
      false
    end

    private

    def email_must_be_unique
      return if email.blank?

      if User.exists?(email: email)
        errors.add(:email, "このemailアドレスはすでに使われています")
      end
    end
  end
end
