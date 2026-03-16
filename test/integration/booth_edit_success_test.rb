# frozen_string_literal: true

require "test_helper"

class BoothEditSuccessTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess

  setup do
    @store1 = Store.create!(name: "store1")
    @booth1 = Booth.create!(store: @store1, name: "booth1", status: :offline)

    @cast = User.create!(email: "cast86@example.com", password: "password", role: :cast)
    BoothCast.create!(booth: @booth1, cast_user: @cast)

    @store_admin = User.create!(email: "admin86@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)

    @customer = User.create!(email: "cust86@example.com", password: "password", role: :customer)
  end

  test "cast can update description and attach thumbnail" do
    sign_in @cast, scope: :user

    file = fixture_file_upload(Rails.root.join("test/fixtures/files/thumb.png"), "image/png")

    patch cast_booth_path(@booth1), params: {
      booth: { description: "new desc", thumbnail_image: file }
    }

    assert_redirected_to cast_booths_path

    @booth1.reload
    assert_equal "new desc", @booth1.description
    assert @booth1.thumbnail_image.attached?
  end

  test "store_admin can update description and attach thumbnail" do
    sign_in @store_admin, scope: :user

    file = fixture_file_upload(Rails.root.join("test/fixtures/files/thumb.png"), "image/png")

    patch admin_booth_path(@booth1), params: {
      booth: { description: "admin desc", thumbnail_image: file }
    }

    assert_redirected_to admin_booth_path(@booth1)

    @booth1.reload
    assert_equal "admin desc", @booth1.description
    assert @booth1.thumbnail_image.attached?
  end

  test "customer does not see edit link on public booth show" do
    sign_in @customer, scope: :user

    get booth_path(@booth1)
    assert_response :success

    assert_not_includes response.body, "編集"
    assert_not_includes response.body, "ブース編集"
  end
end
