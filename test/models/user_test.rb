# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "bio is optional (nil is allowed)" do
    user = User.new(email: "bio_nil@example.com", password: "password", role: :customer, bio: nil)
    assert user.valid?
  end

  test "bio length must be <= 500" do
    user = User.new(email: "bio_len@example.com", password: "password", role: :customer)

    user.bio = "a" * 500
    assert user.valid?

    user.bio = "a" * 501
    assert_not user.valid?
    assert_includes user.errors.details[:bio], { error: :too_long, count: 500 }
  end

  test "store registration proxy is allowed by an admin membership in a sales support company" do
    user = create_store_admin("proxy-allowed@example.com")
    support_company = Store.create!(name: "Support Company", sales_support_company: true)
    StoreMembership.create!(store: support_company, user:, membership_role: :admin)

    assert user.store_registration_proxy_allowed?
  end

  test "store registration proxy is not allowed by a regular store or cast membership" do
    user = create_store_admin("proxy-denied@example.com")
    regular_store = Store.create!(name: "Regular Store")
    support_company = Store.create!(name: "Support Company", sales_support_company: true)
    StoreMembership.create!(store: regular_store, user:, membership_role: :admin)
    StoreMembership.create!(store: support_company, user:, membership_role: :cast)

    assert_not user.store_registration_proxy_allowed?
  end

  test "store registration proxy immediately reflects support company and membership changes" do
    user = create_store_admin("proxy-dynamic@example.com")
    first_company = Store.create!(name: "First Company", sales_support_company: true)
    second_company = Store.create!(name: "Second Company", sales_support_company: true)
    first_membership = StoreMembership.create!(store: first_company, user:, membership_role: :admin)
    second_membership = StoreMembership.create!(store: second_company, user:, membership_role: :admin)

    first_company.update!(sales_support_company: false)
    assert user.store_registration_proxy_allowed?

    second_company.update!(sales_support_company: false)
    assert_not user.store_registration_proxy_allowed?

    first_company.update!(sales_support_company: true)
    assert user.store_registration_proxy_allowed?

    first_membership.destroy!
    assert_not user.store_registration_proxy_allowed?

    second_company.update!(sales_support_company: true)
    assert user.store_registration_proxy_allowed?

    second_membership.update!(membership_role: :cast)
    assert_not user.store_registration_proxy_allowed?
  end

  test "store registration proxy is not allowed for a stopped store admin" do
    user = create_store_admin("proxy-stopped@example.com", deleted_at: Time.current)
    support_company = Store.create!(name: "Support Company", sales_support_company: true)
    StoreMembership.create!(store: support_company, user:, membership_role: :admin)

    assert_not user.store_registration_proxy_allowed?
  end

  private

  def create_store_admin(email, deleted_at: nil)
    User.create!(
      email:,
      password: "password",
      role: :store_admin,
      deleted_at:
    )
  end
end
