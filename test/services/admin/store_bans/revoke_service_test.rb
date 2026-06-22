# frozen_string_literal: true

require "test_helper"

class Admin::StoreBans::RevokeServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "store-ban-revoke-service")
    @admin = User.create!(email: "store_ban_revoke_admin@example.com", password: "password", role: :system_admin)
    @customer = User.create!(email: "store_ban_revoke_customer@example.com", password: "password", role: :customer)
    @store_ban = StoreBan.create!(store: @store, customer_user: @customer, created_by_store_admin_user: @admin)
  end

  test "revokes without deleting record" do
    assert_no_difference "StoreBan.count" do
      result = Admin::StoreBans::RevokeService.new(
        store_ban: @store_ban,
        actor: @admin,
        reason: "mistake"
      ).call

      assert result.revoked
    end

    assert @store_ban.reload.revoked?
    assert_equal @admin, @store_ban.revoked_by_user
    assert_equal "mistake", @store_ban.revocation_reason
  end

  test "already revoked is success without update" do
    @store_ban.update!(revoked_at: Time.current, revoked_by_user: @admin)

    result = Admin::StoreBans::RevokeService.new(store_ban: @store_ban, actor: @admin).call

    assert_not result.revoked
  end
end
