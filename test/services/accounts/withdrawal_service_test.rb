# frozen_string_literal: true

require "test_helper"

class Accounts::WithdrawalServiceTest < ActiveSupport::TestCase
  test "customer retirement preserves wallet balance and pending purchases" do
    customer = create_user("withdrawal-customer", :customer)
    wallet = Wallet.create!(customer_user: customer, available_points: 1200, reserved_points: 300)
    purchase = WalletPurchase.create!(wallet:, points: 500, status: :pending)

    Accounts::WithdrawalService.new(user: customer).call!

    assert customer.reload.deleted?
    assert_equal 1200, wallet.reload.available_points
    assert_equal 300, wallet.reserved_points
    assert purchase.reload.pending?
  end

  test "cast retirement removes every store membership and archives every related booth" do
    cast = create_user("withdrawal-cast", :cast)
    stores = [ Store.create!(name: "Cast Store 1"), Store.create!(name: "Cast Store 2") ]
    memberships = stores.map do |store|
      StoreMembership.create!(store:, user: cast, membership_role: :cast)
    end
    booths = stores.map.with_index do |store, index|
      Booth.create!(store:, name: "Cast Booth #{index}", status: :offline).tap do |booth|
        BoothCast.create!(booth:, cast_user: cast)
      end
    end

    Accounts::WithdrawalService.new(user: cast).call!

    assert cast.reload.deleted?
    memberships.each { |membership| assert_not StoreMembership.exists?(membership.id) }
    booths.each { |booth| assert booth.reload.archived? }
  end

  test "shared stores keep their state while sole-admin stores are closed" do
    admin = create_user("withdrawal-admin", :store_admin)
    other_admin = create_user("withdrawal-other-admin", :store_admin)
    cast = create_user("withdrawal-store-cast", :cast)

    shared_store = Store.create!(name: "Shared Store", published: false)
    sole_store = Store.create!(name: "Sole Store", published: true)
    StoreMembership.create!(store: shared_store, user: admin, membership_role: :admin)
    StoreMembership.create!(store: shared_store, user: other_admin, membership_role: :admin)
    sole_admin_membership = StoreMembership.create!(store: sole_store, user: admin, membership_role: :admin)

    shared_cast_membership = StoreMembership.create!(store: shared_store, user: cast, membership_role: :cast)
    sole_cast_membership = StoreMembership.create!(store: sole_store, user: cast, membership_role: :cast)
    shared_booth = Booth.create!(store: shared_store, name: "Shared Booth", status: :offline)
    sole_assigned_booth = Booth.create!(store: sole_store, name: "Assigned Booth", status: :offline)
    sole_unassigned_booth = Booth.create!(store: sole_store, name: "Unassigned Booth", status: :offline)
    BoothCast.create!(booth: shared_booth, cast_user: cast)
    BoothCast.create!(booth: sole_assigned_booth, cast_user: cast)

    shared_invitation = create_cast_invitation(shared_store, admin, "shared")
    sole_cast_invitation = create_cast_invitation(sole_store, admin, "sole-cast")
    sole_admin_invitation = create_admin_invitation(sole_store, admin, "sole-admin")

    Accounts::WithdrawalService.new(user: admin).call!

    assert admin.reload.deleted?
    assert_not shared_store.reload.published?
    assert_not shared_booth.reload.archived?
    assert StoreMembership.exists?(shared_cast_membership.id)
    assert shared_invitation.reload.usable?

    assert_not sole_store.reload.published?
    assert sole_assigned_booth.reload.archived?
    assert sole_unassigned_booth.reload.archived?
    assert_not StoreMembership.exists?(sole_cast_membership.id)
    assert StoreMembership.exists?(sole_admin_membership.id)
    assert_not cast.reload.deleted?
    assert_not sole_cast_invitation.reload.usable?
    assert_not sole_admin_invitation.reload.usable?
  end

  test "a retired co-admin is not counted as an active administrator" do
    admin = create_user("withdrawal-only-active-admin", :store_admin)
    retired_admin = create_user("withdrawal-retired-admin", :store_admin, deleted_at: Time.current)
    store = Store.create!(name: "Retired Co-admin Store", published: true)
    StoreMembership.create!(store:, user: admin, membership_role: :admin)
    StoreMembership.create!(store:, user: retired_admin, membership_role: :admin)

    Accounts::WithdrawalService.new(user: admin).call!

    assert_not store.reload.published?
  end

  test "failure leaves the user active and can be retried after the state is repaired" do
    cast = create_user("withdrawal-retry-cast", :cast)
    store = Store.create!(name: "Retry Store")
    membership = StoreMembership.create!(store:, user: cast, membership_role: :cast)
    booth = Booth.create!(store:, name: "Broken Booth", status: :live)
    BoothCast.create!(booth:, cast_user: cast)

    assert_raises Booths::CloseAndArchiveService::InconsistentState do
      Accounts::WithdrawalService.new(user: cast).call!
    end

    assert_not cast.reload.deleted?
    assert StoreMembership.exists?(membership.id)
    assert_not booth.reload.archived?

    booth.update!(status: :offline)
    Accounts::WithdrawalService.new(user: cast).call!

    assert cast.reload.deleted?
    assert booth.reload.archived?
  end

  test "system administrators cannot retire themselves" do
    system_admin = create_user("withdrawal-system-admin", :system_admin)

    assert_raises Accounts::WithdrawalService::NotAllowed do
      Accounts::WithdrawalService.new(user: system_admin).call!
    end

    assert_not system_admin.reload.deleted?
  end

  test "an already retired user is an idempotent success" do
    customer = create_user("withdrawal-already-retired", :customer, deleted_at: Time.current)

    result = Accounts::WithdrawalService.new(user: customer).call!

    assert result.already_withdrawn
  end

  private

  def create_user(prefix, role, deleted_at: nil)
    User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role:,
      deleted_at:
    )
  end

  def create_cast_invitation(store, actor, suffix)
    StoreCastInvitation.create!(
      store:,
      invited_by_user: actor,
      token_digest: "cast-#{suffix}",
      expires_at: 1.day.from_now
    )
  end

  def create_admin_invitation(store, actor, suffix)
    StoreAdminInvitation.create!(
      store:,
      invited_by_user: actor,
      token_digest: "admin-#{suffix}",
      expires_at: 1.day.from_now
    )
  end
end
