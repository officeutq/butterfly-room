# frozen_string_literal: true

require "test_helper"

class StoreBanTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "store-ban-model")
    @admin = User.create!(email: "store_ban_model_admin@example.com", password: "password", role: :store_admin)
    @customer = User.create!(email: "store_ban_model_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "store_ban_model_cast@example.com", password: "password", role: :cast)
  end

  test "customer only can be banned" do
    ban = StoreBan.new(store: @store, customer_user: @cast, created_by_store_admin_user: @admin)

    assert_not ban.valid?
    assert ban.errors[:customer_user].present?
  end

  test "active ban is unique but revoked ban allows re-ban" do
    first_ban = StoreBan.create!(store: @store, customer_user: @customer, created_by_store_admin_user: @admin)

    duplicate = StoreBan.new(store: @store, customer_user: @customer, created_by_store_admin_user: @admin)
    assert_not duplicate.valid?

    first_ban.update!(revoked_at: Time.current, revoked_by_user: @admin)

    assert_difference "StoreBan.count", 1 do
      StoreBan.create!(store: @store, customer_user: @customer, created_by_store_admin_user: @admin)
    end
  end
end
