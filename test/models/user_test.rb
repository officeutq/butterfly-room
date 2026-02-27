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
    assert_includes user.errors[:bio], "is too long (maximum is 500 characters)"
  end
end
