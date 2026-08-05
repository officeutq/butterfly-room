# frozen_string_literal: true

require "test_helper"

class UserPermissionTest < ActiveSupport::TestCase
  setup do
    @store_admin = User.create!(email: "permission-admin@example.com", password: "password", role: :store_admin)
  end

  test "store_registration_proxy can be granted to an active store_admin" do
    permission = UserPermission.create!(
      user: @store_admin,
      permission_type: "store_registration_proxy"
    )

    assert_equal "店舗責任者の登録代行", permission.label
    assert @store_admin.permitted_for?(:store_registration_proxy)
  end

  test "undefined permission type is invalid" do
    permission = UserPermission.new(user: @store_admin, permission_type: "unknown")

    assert_not permission.valid?
    assert_includes permission.errors.details[:permission_type], { error: :inclusion, value: "unknown" }
  end

  test "same permission cannot be granted twice" do
    UserPermission.create!(user: @store_admin, permission_type: "store_registration_proxy")
    duplicate = UserPermission.new(user: @store_admin, permission_type: "store_registration_proxy")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.details[:permission_type], { error: :taken, value: "store_registration_proxy" }
  end

  test "permission cannot be granted to a disallowed role or stopped user" do
    customer = User.create!(email: "permission-customer@example.com", password: "password", role: :customer)
    wrong_role = UserPermission.new(user: customer, permission_type: "store_registration_proxy")

    assert_not wrong_role.valid?
    assert wrong_role.errors[:user].any?

    @store_admin.update!(deleted_at: Time.current)
    stopped = UserPermission.new(user: @store_admin, permission_type: "store_registration_proxy")

    assert_not stopped.valid?
    assert stopped.errors[:user].any?
  end

  test "permission check also validates the current role and active state" do
    UserPermission.create!(user: @store_admin, permission_type: "store_registration_proxy")

    @store_admin.update!(role: :customer)
    assert_not @store_admin.permitted_for?(:store_registration_proxy)

    @store_admin.update!(role: :store_admin, deleted_at: Time.current)
    assert_not @store_admin.permitted_for?(:store_registration_proxy)
  end
end
