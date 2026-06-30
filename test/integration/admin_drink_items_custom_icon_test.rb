# frozen_string_literal: true

require "test_helper"

class AdminDrinkItemsCustomIconTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess
  include ActiveJob::TestHelper

  setup do
    @store = Store.create!(name: "drink-icon-store")
    @store_admin = User.create!(
      email: "drink-icon-admin@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
    sign_in @store_admin, scope: :user
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "store admin can create drink item with custom_icon" do
    assert_difference("DrinkItem.count", 1) do
      post admin_drink_items_path, params: {
        drink_item: base_drink_item_params.merge(custom_icon: upload_png)
      }
    end

    assert_response :redirect
    assert_redirected_to admin_drink_items_path

    drink_item = DrinkItem.order(:id).last
    assert_equal @store.id, drink_item.store_id
    assert drink_item.custom_icon.attached?
  end

  test "store admin can replace custom_icon" do
    drink_item = create_drink_item_with_custom_icon
    old_blob_id = drink_item.custom_icon.blob.id

    patch admin_drink_item_path(drink_item), params: {
      drink_item: base_drink_item_params.merge(custom_icon: upload_png)
    }

    assert_response :redirect
    assert_redirected_to admin_drink_items_path

    drink_item.reload
    assert drink_item.custom_icon.attached?
    assert_not_equal old_blob_id, drink_item.custom_icon.blob.id
  end

  test "store admin keeps existing custom_icon when file is not selected" do
    drink_item = create_drink_item_with_custom_icon
    old_blob_id = drink_item.custom_icon.blob.id

    patch admin_drink_item_path(drink_item), params: {
      drink_item: base_drink_item_params.merge(name: "ファイル未選択更新")
    }

    assert_response :redirect
    assert_redirected_to admin_drink_items_path

    drink_item.reload
    assert_equal "ファイル未選択更新", drink_item.name
    assert drink_item.custom_icon.attached?
    assert_equal old_blob_id, drink_item.custom_icon.blob.id
  end

  test "store admin can return from custom_icon to preset icon" do
    drink_item = create_drink_item_with_custom_icon

    perform_enqueued_jobs do
      patch admin_drink_item_path(drink_item), params: {
        drink_item: base_drink_item_params.merge(
          icon_key: "mug",
          remove_custom_icon: "1"
        )
      }
    end

    assert_response :redirect
    assert_redirected_to admin_drink_items_path

    drink_item.reload
    assert_not drink_item.custom_icon.attached?
    assert_equal "mug", drink_item.icon_key
  end

  test "validation failure does not purge existing custom_icon" do
    drink_item = create_drink_item_with_custom_icon

    perform_enqueued_jobs do
      patch admin_drink_item_path(drink_item), params: {
        drink_item: base_drink_item_params.merge(
          name: "",
          icon_key: "mug",
          remove_custom_icon: "1"
        )
      }
    end

    assert_response :unprocessable_entity
    assert drink_item.reload.custom_icon.attached?
  end

  test "enabled toggle does not remove custom_icon" do
    drink_item = create_drink_item_with_custom_icon
    old_blob_id = drink_item.custom_icon.blob.id

    patch admin_drink_item_path(drink_item), params: {
      drink_item: base_drink_item_params.merge(
        enabled: "0",
        icon_key: drink_item.icon_key
      )
    }

    assert_response :redirect
    assert_redirected_to admin_drink_items_path

    drink_item.reload
    assert_not drink_item.enabled?
    assert drink_item.custom_icon.attached?
    assert_equal old_blob_id, drink_item.custom_icon.blob.id
  end

  private

  def base_drink_item_params
    {
      name: "カスタムドリンク",
      price_points: "1200",
      position: "1",
      enabled: "1",
      icon_key: ""
    }
  end

  def create_drink_item_with_custom_icon
    drink_item = DrinkItem.create!(
      store: @store,
      name: "既存カスタム",
      price_points: 1000,
      position: 1,
      enabled: true,
      icon_key: "champagne"
    )
    drink_item.custom_icon.attach(upload_png)
    drink_item
  end

  def upload_png
    fixture_file_upload(Rails.root.join("test/fixtures/files/thumb.png"), "image/png")
  end
end
