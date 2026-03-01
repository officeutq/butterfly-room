# frozen_string_literal: true

module StoreAdmins
  class RegisterStoreAdmin
    Result = Struct.new(:user, keyword_init: true)

    def self.call!(email:, password:)
      new(email:, password:).call!
    end

    def initialize(email:, password:)
      @email = email
      @password = password
    end

    def call!
      user = nil

      ActiveRecord::Base.transaction do
        user = User.create!(
          email: @email,
          password: @password,
          password_confirmation: @password,
          role: :store_admin
        )
      end

      Result.new(user: user)
    end
  end
end
