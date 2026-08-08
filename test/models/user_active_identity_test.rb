# frozen_string_literal: true

require "test_helper"

class UserActiveIdentityTest < ActiveSupport::TestCase
  test "email and phone indexes are unique only for active users" do
    indexes = ActiveRecord::Base.connection.indexes(:users).index_by(&:name)

    email_index = indexes.fetch("index_users_on_email")
    phone_index = indexes.fetch("index_users_on_phone_number")

    assert email_index.unique
    assert phone_index.unique
    assert_includes email_index.where, "deleted_at IS NULL"
    assert_includes phone_index.where, "deleted_at IS NULL"
  end

  test "a retired email and phone can be reused by a new active user" do
    retired = create_user(
      email: "reusable@example.com",
      phone_number: "+819012345678",
      deleted_at: Time.current
    )

    active = create_user(
      email: retired.email,
      phone_number: retired.phone_number
    )

    assert active.persisted?
    assert_not_equal retired.id, active.id
  end

  test "multiple retired users can keep the same email and phone" do
    first = create_user(
      email: "retired-duplicate@example.com",
      phone_number: "+819022222222",
      deleted_at: 2.days.ago
    )
    second = create_user(
      email: first.email,
      phone_number: first.phone_number,
      deleted_at: 1.day.ago
    )

    assert second.persisted?
    assert_not_equal first.id, second.id
  end

  test "email and phone remain unique between active users" do
    create_user(email: "active-unique@example.com", phone_number: "+819011111111")

    duplicate = User.new(
      email: "active-unique@example.com",
      phone_number: "+819011111111",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:email, :taken, value: duplicate.email)
    assert duplicate.errors.added?(:phone_number, :taken, value: duplicate.phone_number)
  end

  test "devise authentication and password reset select the active account" do
    retired = create_user(email: "same-login@example.com", deleted_at: Time.current)
    active = create_user(email: retired.email)

    authenticated = User.find_for_database_authentication(email: retired.email)
    assert_equal active.id, authenticated.id

    recoverable = User.send_reset_password_instructions(email: retired.email)
    assert_equal active.id, recoverable.id
    assert active.reload.reset_password_token.present?
    assert_nil retired.reload.reset_password_token
  end

  test "a retired account reset token cannot be used" do
    retired = create_user(email: "retired-token@example.com", deleted_at: Time.current)
    raw_token = retired.send(:set_reset_password_token)

    assert_nil User.with_reset_password_token(raw_token)
  end

  test "customer registration form ignores a retired email" do
    retired = create_user(email: "retired-signup@example.com", deleted_at: Time.current)
    form = Customers::RegistrationForm.new(
      email: retired.email,
      password: "password",
      password_confirmation: "password"
    )

    assert_difference "User.count", 1 do
      assert form.save
    end
    assert_not_equal retired.id, form.user.id
  end

  private

  def create_user(email:, phone_number: nil, deleted_at: nil)
    User.create!(
      email:,
      phone_number:,
      phone_verified_at: (Time.current if phone_number.present?),
      password: "password",
      password_confirmation: "password",
      role: :customer,
      deleted_at:
    )
  end
end
