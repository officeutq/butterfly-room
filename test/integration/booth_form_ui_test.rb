# frozen_string_literal: true

require "test_helper"

class BoothFormUiTest < ActionDispatch::IntegrationTest
  test "cast sees the integrated edit form in booth detail order" do
    cast = create_user("booth-form-cast", :cast)
    store = Store.create!(name: "所属店舗A")
    booth = Booth.create!(store:, name: "編集対象ブース", description: "説明文")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user
    get edit_cast_booth_path(booth)

    assert_response :success
    assert_select "header#app_header .header-title", text: "ブース編集", count: 1
    assert_integrated_booth_form(submit_label: "保存", back_path: dashboard_path) do
      assert_select ".booth-form__readonly-card:not([data-bs-theme])", count: 1 do
        assert_select ".booth-form__readonly-section", count: 2
        assert_select ".booth-form__readonly-label", text: "所属キャスト", count: 1
        assert_select ".booth-form__cast-value", text: /#{Regexp.escape(cast.display_name)}/, count: 1
        assert_select ".booth-form__readonly-label", text: "所属店舗", count: 1
        assert_select ".booth-form__readonly-value", text: store.name, count: 1
      end
      assert_select "select[name='booth_cast[cast_user_id]']", count: 0
    end

    assert_detail_order
  end

  test "store admin sees the same creation form with an assignable cast" do
    admin = create_user("booth-form-admin", :store_admin)
    cast = create_user("booth-form-option", :cast)
    store = Store.create!(name: "所属店舗B")
    StoreMembership.create!(store:, user: admin, membership_role: :admin)
    StoreMembership.create!(store:, user: cast, membership_role: :cast)

    sign_in admin, scope: :user
    get new_admin_booth_path

    assert_response :success
    assert_select "header#app_header .header-title", text: "ブース作成", count: 1
    assert_select "main h1", text: "ブース作成", count: 0
    assert_integrated_booth_form(submit_label: "作成", back_path: dashboard_path) do
      assert_select ".form-floating[data-bs-theme='light'] select[name='booth_cast[cast_user_id]']", count: 1 do
        assert_select "option[value='#{cast.id}']", text: cast.display_name, count: 1
      end
      assert_select "label[for='booth_cast_cast_user_id']", text: "所属キャスト", count: 1
      assert_select ".booth-form__readonly-card", count: 0
      assert_select ".booth-form__readonly-label", text: "所属店舗", count: 0
    end

    assert_creation_order
  end

  test "invalid creation remains retryable without another edit" do
    admin = create_user("booth-form-retry-admin", :store_admin)
    store = Store.create!(name: "所属店舗C")
    StoreMembership.create!(store:, user: admin, membership_role: :admin)

    sign_in admin, scope: :user
    post admin_booths_path, params: {
      booth: { name: "a" * 101, description: "再試行する説明" }
    }

    assert_response :unprocessable_entity
    assert_select "form#booth-form[data-booth-form-initial-dirty-value='true']", count: 1 do
      assert_select "input.booth-form__submit[type='submit'][value='作成']:not([disabled])", count: 1
      assert_select "input.booth-form__bottom-submit[type='submit'][value='作成']:not([disabled])", count: 1
      assert_select "input#booth_name[value='#{'a' * 101}']", count: 1
      assert_select "textarea#booth_description", text: "再試行する説明", count: 1
    end
  end

  private

  def create_user(prefix, role)
    User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role:,
      display_name: prefix
    )
  end

  def assert_integrated_booth_form(submit_label:, back_path:)
    assert_select(
      "form#booth-form.booth-form" \
      "[data-controller~='image-pair-form'][data-controller~='booth-form']" \
      "[data-action*='image-attachment-editor:change->booth-form#refresh']",
      count: 1
    ) do
      assert_select ".booth-form__action-bar", count: 1 do
        assert_select ".container.booth-form__action-bar-inner", count: 1 do
          assert_select "a.booth-form__back[href='#{back_path}']", text: /戻る/, count: 1
          assert_select "input.booth-form__submit[type='submit'][value='#{submit_label}'][disabled]", count: 1
        end
      end
      assert_select(
        "#image-attachment-editor-image-pair.integrated-image-editor--cover" \
        "[data-image-attachment-editor-ratio-key-value='social']" \
        "[data-image-attachment-editor-keep-staged-actions-value='true']",
        count: 1
      )
      assert_select ".form-floating[data-bs-theme='light']", minimum: 2
      assert_select ".form-floating input#booth_name[required][placeholder='ブース名']", count: 1
      assert_select ".form-floating textarea#booth_description[placeholder='説明文']", count: 1
      assert_select "[data-image-pair-form-target='error'][role='alert'][hidden]", count: 1
      assert_select ".booth-form__bottom-actions", count: 1 do
        assert_select "input.booth-form__bottom-submit[type='submit'][value='#{submit_label}']" \
                      "[data-image-pair-form-target='submitButton'][data-booth-form-target='submitButton']",
                      count: 1
      end
      yield
    end
  end

  def assert_detail_order
    form_html = Nokogiri::HTML(response.body).at_css("#booth-form").to_html

    assert_appears_before(form_html, "image-attachment-editor-image-pair", 'id="booth_name"')
    assert_appears_before(form_html, 'id="booth_name"', "所属キャスト")
    assert_appears_before(form_html, "所属キャスト", "所属店舗")
    assert_appears_before(form_html, "所属店舗", 'id="booth_description"')
  end

  def assert_creation_order
    form_html = Nokogiri::HTML(response.body).at_css("#booth-form").to_html

    assert_appears_before(form_html, "image-attachment-editor-image-pair", 'id="booth_name"')
    assert_appears_before(form_html, 'id="booth_name"', "所属キャスト")
    assert_appears_before(form_html, "所属キャスト", 'id="booth_description"')
  end

  def assert_appears_before(html, first, second)
    first_position = html.index(first)
    second_position = html.index(second)

    assert first_position, "#{first.inspect} がレスポンスにありません"
    assert second_position, "#{second.inspect} がレスポンスにありません"
    assert_operator first_position, :<, second_position
  end
end
