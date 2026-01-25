# frozen_string_literal: true

module Authorization
  class StoreBanChecker
    def initialize(store:, user:)
      @store = store
      @user = user
    end

    def banned?
      return false if @store.blank? || @user.blank?
      return false unless @user.customer?

      StoreBan.exists?(store_id: @store.id, customer_user_id: @user.id)
    end
  end
end
