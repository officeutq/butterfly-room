# frozen_string_literal: true

module Accounts
  class ChangeEmailService
    def initialize(user:, attributes:)
      @user = user
      @attributes = attributes
    end

    def call
      @user.with_lock { @user.update_with_password(@attributes) }
    rescue ActiveRecord::RecordNotUnique
      @user.errors.add(:email, :taken)
      false
    end
  end
end
