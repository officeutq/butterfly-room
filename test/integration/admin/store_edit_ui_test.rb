# frozen_string_literal: true

require "test_helper"

class Admin::StoreEditUiTest < ActionDispatch::IntegrationTest
  test "store admin sees the profile-based store edit layout in the intended order" do
    user = create_user("store-edit-ui-admin", :store_admin)
    store = Store.create!(name: "店舗編集UI")
    StoreMembership.create!(store:, user:, membership_role: :admin)

    sign_in user, scope: :user
    get edit_admin_store_path(store)

    assert_response :success
    assert_select "header#app_header .header-title", text: "店舗設定編集", count: 1
    assert_select(
      "form#store-edit-form.store-edit" \
      "[data-controller~='image-pair-form'][data-controller~='store-edit']",
      count: 1
    ) do
      assert_select ".store-edit__action-bar", count: 1 do
        assert_select ".container.store-edit__action-bar-inner", count: 1 do
          assert_select "a.store-edit__back[href='#{dashboard_path}']", text: /戻る/, count: 1
          assert_select "input.store-edit__save[type='submit'][value='保存'][disabled]", count: 1
        end
      end

      assert_select ".store-information-fields", count: 1 do
        assert_select(
          "#image-attachment-editor-image-pair.integrated-image-editor--cover" \
          "[data-image-attachment-editor-ratio-key-value='social']" \
          "[data-image-attachment-editor-keep-staged-actions-value='true']",
          count: 1
        )
        assert_select ".form-floating[data-bs-theme='light'] input#store_name[required][placeholder='店舗名']", count: 1
        assert_select ".store-information-fields__ai.pt-3 button.btn-warning[data-store-ai-autofill-target='searchButton']",
                      text: /AIで店舗情報を自動入力/,
                      count: 1
        assert_select ".form-floating[data-bs-theme='light']", count: 12
        assert_select ".form-floating[data-bs-theme='light'] .form-control", count: 11
        assert_select ".form-floating[data-bs-theme='light'] select#store_business_type.form-select", count: 1
        assert_select ".form-floating label", text: "概要", count: 1
      end

      assert_select ".form-floating[data-bs-theme='light'] select#store_published.form-select", count: 1
      assert_select "input#store_sales_support_company", count: 0
      assert_select "[data-image-pair-form-target='error'][role='alert'][hidden]", count: 1
      assert_select ".store-edit__bottom-actions", count: 1 do
        assert_select "input.store-edit__bottom-save[type='submit'][value='保存'][disabled]" \
                      "[data-image-pair-form-target='submitButton'][data-store-edit-target='saveButton']",
                      count: 1
      end
    end

    assert_appears_before("image-attachment-editor-image-pair", 'id="store_name"')
    assert_appears_before('id="store_name"', 'data-store-ai-autofill-target="searchButton"')
    assert_appears_before('data-store-ai-autofill-target="searchButton"', 'id="store_area"')
    assert_appears_before('id="store_area"', 'id="store_business_type"')
    assert_appears_before('id="store_business_type"', 'id="store_address"')
    assert_appears_before('id="store_address"', 'id="store_phone_number"')
    assert_appears_before('id="store_phone_number"', 'id="store_business_hours"')
    assert_appears_before('id="store_business_hours"', 'id="store_website_url"')
    assert_appears_before('id="store_website_url"', 'id="store_x_url"')
    assert_appears_before('id="store_x_url"', 'id="store_instagram_url"')
    assert_appears_before('id="store_instagram_url"', 'id="store_tiktok_url"')
    assert_appears_before('id="store_tiktok_url"', 'id="store_youtube_url"')
    assert_appears_before('id="store_youtube_url"', 'id="store_description"')
    assert_appears_before('id="store_description"', 'id="store_published"')
  end

  test "system admin sees sales support company after published" do
    user = create_user("store-edit-ui-system", :system_admin)
    store = Store.create!(name: "システム管理者店舗")

    sign_in user, scope: :user
    get edit_admin_store_path(store)

    assert_response :success
    assert_select "select#store_published", count: 1
    assert_select "input#store_sales_support_company", count: 1
    assert_appears_before('id="store_published"', 'id="store_sales_support_company"')
  end

  private

  def create_user(prefix, role)
    User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role:
    )
  end

  def assert_appears_before(first, second)
    first_position = response.body.index(first)
    second_position = response.body.index(second)

    assert first_position, "#{first.inspect} がレスポンスにありません"
    assert second_position, "#{second.inspect} がレスポンスにありません"
    assert_operator first_position, :<, second_position
  end
end
