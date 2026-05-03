# frozen_string_literal: true

require "test_helper"

class AdminBoothCastsTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store1")

    @store_admin = User.create!(
      email: "admin_bc@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)

    @booth = Booth.create!(store: @store, name: "booth1", status: :offline)

    @cast1 = User.create!(email: "cast1@example.com", password: "password", role: :cast)
    @cast2 = User.create!(email: "cast2@example.com", password: "password", role: :cast)

    StoreMembership.create!(store: @store, user: @cast1, membership_role: :cast)
    StoreMembership.create!(store: @store, user: @cast2, membership_role: :cast)
  end

  test "store_admin can link cast to booth from edit when unset" do
    sign_in @store_admin, scope: :user

    patch cast_booth_path(@booth), params: {
      booth: {
        name: @booth.name,
        description: @booth.description
      },
      booth_cast: {
        cast_user_id: @cast1.id
      }
    }

    assert_response :redirect

    assert_equal 1, BoothCast.where(booth_id: @booth.id).count
    assert_equal @cast1.id, BoothCast.find_by(booth_id: @booth.id).cast_user_id
  end

  test "cannot create second booth_cast for same booth from edit Phase1 lock" do
    sign_in @store_admin, scope: :user

    BoothCast.create!(booth: @booth, cast_user: @cast1)

    patch cast_booth_path(@booth), params: {
      booth: {
        name: @booth.name,
        description: @booth.description
      },
      booth_cast: {
        cast_user_id: @cast2.id
      }
    }

    assert_response :redirect
    assert_redirected_to edit_cast_booth_path(@booth)

    assert_equal 1, BoothCast.where(booth_id: @booth.id).count
    assert_equal @cast1.id, BoothCast.find_by(booth_id: @booth.id).cast_user_id
  end
end
