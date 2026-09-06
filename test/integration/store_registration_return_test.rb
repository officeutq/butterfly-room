# frozen_string_literal: true

require "test_helper"

class StoreRegistrationReturnTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "new registration identifies the email as the store administrator email" do
    get stores_new_registration_path(ref: "1001")

    assert_response :success
    assert_select "label[for='store_registration_email']",
      text: "店舗管理者のメールアドレス",
      count: 1
    assert_select "input#store_registration_email[name='store_registration[email]'][type='email']", count: 1
  end

  test "new registration falls back to current store LP when from is missing" do
    get stores_new_registration_path(ref: "1001")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path
    assert_select "a[href=?]", stores_lp_path, text: "戻る"
    assert_select "a[href=?][data-turbo-prefetch]", stores_lp_path, count: 0
  end

  test "new registration keeps back link for current store LP" do
    get stores_new_registration_path(ref: "1001", from: "stores_lp")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp")
    assert_select "a[href=?]", stores_lp_path, text: "戻る"
    assert_select "a[href=?][data-turbo-prefetch]", stores_lp_path, count: 0
  end

  test "new registration keeps back link for store LP 202607" do
    get stores_new_registration_path(ref: "1001", from: "stores_lp_202607")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp_202607")
    assert_select "a[href=?]", stores_lp_202607_return_path, text: "戻る"
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
  end

  test "new registration allows blank referral code for store LP 202607" do
    get stores_new_registration_path(from: "stores_lp_202607")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp_202607")
    assert_select "input[name='store_registration[referral_code]']", count: 1
    assert_select "input[name='store_registration[referral_code]'][required]", count: 0
    assert_select "a[href=?]", stores_lp_202607_return_path, text: "戻る"
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
  end

  test "new registration keeps 202607 attribution in session without exposing utm params in action" do
    get stores_lp_202607_path, params: {
      utm_source: " meta ",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607",
      utm_content: "flyer_a"
    }
    get stores_new_registration_path(ref: "1001", from: "stores_lp_202607")

    assert_response :success
    assert_select "form[action=?]",
      stores_registrations_path(from: "stores_lp_202607")
    assert_no_match(/utm_source/, response.body)
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
  end

  test "store LP 202607 return keeps attribution and ref through successful registration" do
    referral_code = create_referral_code!("1001")
    get stores_lp_202607_path, params: {
      ref: referral_code.code,
      utm_source: "meta",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607",
      utm_content: "creative_a"
    }

    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal referral_code.code, @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]

    get stores_new_registration_path(ref: referral_code.code, from: "stores_lp_202607")

    assert_response :success
    assert_select "a[href=?]", stores_lp_202607_return_path, text: "戻る"
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
    assert_select "input[name='store_registration[referral_code]'][value=?]", referral_code.code

    get stores_lp_202607_return_path

    assert_redirected_to stores_lp_202607_path(ref: referral_code.code)

    follow_redirect!

    assert_response :success
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal referral_code.code, @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
    assert_select "a[href=?]", stores_new_registration_path(ref: referral_code.code, from: "stores_lp_202607"), minimum: 1
    assert_no_match(/utm_source/, response.body)

    assert_difference -> { Store.count }, +1 do
      assert_difference -> { User.count }, +1 do
        assert_difference -> { StoreMembership.count }, +1 do
          post stores_registrations_path(from: "stores_lp_202607"), params: {
            store_registration: valid_registration_params(referral_code: referral_code.code)
          }
        end
      end
    end

    store = Store.order(:id).last

    assert_redirected_to edit_admin_store_registration_setup_path(store)
    assert_equal referral_code, store.referral_code

    complete_registration_setup(store)
    assert_redirected_to stores_registration_thanks_path

    follow_redirect!

    assert_equal(
      [
        {
          "event" => "store_registration_complete",
          "from" => "stores_lp_202607",
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "store_recruit_202607",
          "utm_content" => "creative_a"
        }
      ],
      data_layer_events
    )
    assert_nil @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    assert_nil @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
    refute_includes data_layer_events.first.keys, "ref"
    refute_includes data_layer_events.first.keys, "referral_code"
  end

  test "store LP 202607 Turbo return reload keeps attribution through successful registration" do
    referral_code = create_referral_code!("STORE-REG-TURBO-RETURN")
    get stores_lp_202607_path, params: {
      ref: referral_code.code,
      utm_source: "test_meta",
      utm_medium: "paid_social",
      utm_campaign: "return_registration_test",
      utm_content: "creative_registration"
    }

    get stores_new_registration_path(ref: referral_code.code, from: "stores_lp_202607")

    assert_response :success
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"

    get stores_lp_202607_return_path, headers: { "X-Turbo-Request-ID" => "turbo-return" }

    assert_redirected_to stores_lp_202607_path(ref: referral_code.code)

    get stores_lp_202607_path(ref: referral_code.code), headers: { "X-Turbo-Request-ID" => "turbo-lp-fetch" }

    assert_response :success
    assert_equal true, @request.session[ApplicationController::PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY]
    assert_equal "test_meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]

    get stores_lp_202607_path(ref: referral_code.code)

    assert_response :success
    assert_nil @request.session[ApplicationController::PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY]
    assert_equal "test_meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]

    assert_difference -> { Store.count }, +1 do
      assert_difference -> { User.count }, +1 do
        assert_difference -> { StoreMembership.count }, +1 do
          post stores_registrations_path(from: "stores_lp_202607"), params: {
            store_registration: valid_registration_params(referral_code: referral_code.code)
          }
        end
      end
    end

    store = Store.order(:id).last
    assert_redirected_to edit_admin_store_registration_setup_path(store)

    complete_registration_setup(store)
    follow_redirect!

    assert_equal(
      [
        {
          "event" => "store_registration_complete",
          "from" => "stores_lp_202607",
          "utm_source" => "test_meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "return_registration_test",
          "utm_content" => "creative_registration"
        }
      ],
      data_layer_events
    )
  end

  test "contact completion return keeps attribution and ref for later registration" do
    referral_code = create_referral_code!("1001")
    get stores_lp_202607_path, params: {
      ref: referral_code.code,
      utm_source: "meta",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607"
    }

    assert_difference -> { StoreContactSubmission.count }, +1 do
      post stores_contact_path(from: "stores_lp_202607"), params: contact_submission_params
    end

    follow_redirect!

    assert_equal(
      [
        {
          "event" => "store_contact_complete",
          "from" => "stores_lp_202607",
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "store_recruit_202607"
        }
      ],
      data_layer_events
    )
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal referral_code.code, @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]

    get stores_lp_202607_return_path
    follow_redirect!

    assert_select "a[href=?]", stores_new_registration_path(ref: referral_code.code, from: "stores_lp_202607"), minimum: 1

    assert_difference -> { Store.count }, +1 do
      assert_difference -> { User.count }, +1 do
        assert_difference -> { StoreMembership.count }, +1 do
          post stores_registrations_path(from: "stores_lp_202607"), params: {
            store_registration: valid_registration_params(referral_code: referral_code.code)
          }
        end
      end
    end

    store = Store.order(:id).last
    assert_equal referral_code, store.referral_code

    assert_redirected_to edit_admin_store_registration_setup_path(store)
    complete_registration_setup(store)
    follow_redirect!

    assert_equal(
      [
        {
          "event" => "store_registration_complete",
          "from" => "stores_lp_202607",
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "store_recruit_202607"
        }
      ],
      data_layer_events
    )
  end

  test "new registration falls back to current store LP when from is invalid" do
    get stores_new_registration_path(ref: "1001", from: "https://example.com")

    assert_response :success
    assert_select "form[action=?]", stores_registrations_path
    assert_select "a[href=?]", stores_lp_path, text: "戻る"
    assert_select "a[href=?][data-turbo-prefetch]", stores_lp_path, count: 0
    assert_no_match "https://example.com", response.body
  end

  test "validation errors keep store LP 202607 back link" do
    assert_no_difference -> { Store.count } do
      post stores_registrations_path(from: "stores_lp_202607"), params: {
        store_registration: {
          store_name: "",
          email: "",
          password: "",
          password_confirmation: "",
          referral_code: ""
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?]", stores_registrations_path(from: "stores_lp_202607")
    assert_select "a[href=?]", stores_lp_202607_return_path, text: "戻る"
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
  end

  test "validation errors keep ref and 202607 attribution session" do
    referral_code = create_referral_code!("STORE-REG-RETURN-ERROR")
    get stores_lp_202607_path, params: {
      utm_source: "meta",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607"
    }

    assert_no_difference -> { Store.count } do
      post stores_registrations_path(from: "stores_lp_202607"), params: {
        store_registration: valid_registration_params(
          store_name: "",
          referral_code: referral_code.code
        )
      }
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?]",
      stores_registrations_path(from: "stores_lp_202607")
    assert_select "input[name='store_registration[referral_code]'][value=?]", referral_code.code
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_no_match(/utm_source/, response.body)
  end

  test "successful registration completes after initial setup and keeps existing admin edit destination" do
    referral_code = create_referral_code!("STORE-REG-RETURN-OK")
    get stores_lp_202607_path, params: {
      utm_source: "meta",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607"
    }

    assert_difference -> { Store.count }, +1 do
      assert_difference -> { User.count }, +1 do
        assert_difference -> { StoreMembership.count }, +1 do
          post stores_registrations_path(from: "stores_lp_202607"), params: {
            store_registration: valid_registration_params(referral_code: referral_code.code)
          }
        end
      end
    end

    store = Store.order(:id).last

    assert_redirected_to edit_admin_store_registration_setup_path(store)
    assert_no_match(/ref=/, response.location)
    assert_no_match(/utm_/, response.location)
    assert_equal referral_code, store.referral_code
    assert_not store.published?
    assert_equal store.id, @request.session[:current_store_id].to_i
    assert_equal(
      {
        "from" => "stores_lp_202607",
        "utm" => {
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "store_recruit_202607"
        },
        "store_id" => store.id
      },
      @request.session[:store_registration_pending]
    )
    assert_nil @request.session[:store_registration_completion]

    complete_registration_setup(store)
    thanks_path = URI(response.location).request_uri

    assert_redirected_to stores_registration_thanks_path
    assert_predicate store.reload, :published?
    assert_nil @request.session[:store_registration_pending]
    assert_equal(
      {
        "from" => "stores_lp_202607",
        "utm" => {
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "store_recruit_202607"
        },
        "store_id" => store.id
      },
      @request.session[:store_registration_completion]
    )

    follow_redirect!

    assert_response :success
    assert_select "h1", text: "店舗情報の登録・公開が完了しました"
    assert_select "a[href=?]", dashboard_path, text: "ダッシュボードへ進む"
    assert_equal(
      [
        {
          "event" => "store_registration_complete",
          "from" => "stores_lp_202607",
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "store_recruit_202607"
        }
      ],
      data_layer_events
    )
    assert_nil @request.session[:store_registration_completion]
    assert_nil @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]
    refute_includes data_layer_events.first.keys, "store_id"
    refute_includes data_layer_events.first.keys, "user_id"
    refute_includes data_layer_events.first.keys, "ref"
    refute_includes data_layer_events.first.keys, "referral_code"

    get dashboard_path
    assert_response :success
    assert_select "[data-controller='onboarding'][data-onboarding-step-value='invite_cast']", count: 1

    get thanks_path
    assert_redirected_to edit_admin_store_path(store)
    assert_no_match(/window\.dataLayer\.push/, response.body)
  end

  test "store LP 202609 completion keeps attribution until thanks and then removes it" do
    referral_code = create_referral_code!("STORE-REG-202609-THANKS")
    get stores_lp_202609_path, params: {
      ref: referral_code.code,
      utm_source: "meta_202609",
      utm_campaign: "store_recruit_202609"
    }

    post stores_registrations_path(from: "stores_lp_202609"), params: {
      store_registration: valid_registration_params(referral_code: referral_code.code)
    }
    store = Store.order(:id).last
    assert_redirected_to edit_admin_store_registration_setup_path(store)
    assert_equal "meta_202609",
                 @request.session[ApplicationController::STORE_LP_202609_ATTRIBUTION_SESSION_KEY]["utm_source"]

    complete_registration_setup(store)
    follow_redirect!

    assert_equal(
      [
        {
          "event" => "store_registration_complete",
          "from" => "stores_lp_202609",
          "utm_source" => "meta_202609",
          "utm_campaign" => "store_recruit_202609"
        }
      ],
      data_layer_events
    )
    assert_nil @request.session[ApplicationController::STORE_LP_202609_ATTRIBUTION_SESSION_KEY]
    assert_nil @request.session[ApplicationController::STORE_LP_202609_REF_SESSION_KEY]
  end

  test "current store LP completion emits only the allowed source without UTM" do
    referral_code = create_referral_code!("STORE-REG-CURRENT-LP-THANKS")

    post stores_registrations_path(from: "stores_lp"), params: {
      store_registration: valid_registration_params(referral_code: referral_code.code)
    }
    store = Store.order(:id).last
    assert_redirected_to edit_admin_store_registration_setup_path(store)

    complete_registration_setup(store)
    follow_redirect!

    assert_equal(
      [ { "event" => "store_registration_complete", "from" => "stores_lp" } ],
      data_layer_events
    )
  end

  test "blank referral code defaults to 0000 on successful registration" do
    default_referral_code = create_referral_code!(Stores::RegisterStoreAdmin::DEFAULT_REFERRAL_CODE)

    assert_difference -> { Store.count }, +1 do
      assert_difference -> { User.count }, +1 do
        assert_difference -> { StoreMembership.count }, +1 do
          post stores_registrations_path(from: "stores_lp_202607"), params: {
            store_registration: valid_registration_params(referral_code: "")
          }
        end
      end
    end

    store = Store.order(:id).last

    assert_redirected_to edit_admin_store_registration_setup_path(store)
    assert_no_match(/ref=/, response.location)
    assert_equal default_referral_code, store.referral_code
    assert_equal store.id, @request.session[:current_store_id].to_i

    complete_registration_setup(store)
    assert_redirected_to stores_registration_thanks_path

    follow_redirect!

    assert_response :success
    assert_equal(
      [ { "event" => "store_registration_complete", "from" => "stores_lp_202607" } ],
      data_layer_events
    )
  end

  test "registration thanks requires login" do
    get stores_registration_thanks_path

    assert_redirected_to new_user_session_path
  end

  test "logged in user without completion session is redirected to current store edit" do
    store = Store.create!(name: "No Completion Store")
    user = User.create!(email: "no-completion-store-admin@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: user, membership_role: :admin)
    sign_in user, scope: :user
    post admin_current_store_path, params: { store_id: store.id }

    get stores_registration_thanks_path

    assert_redirected_to edit_admin_store_path(store)
  end

  test "registration thanks rejects completion when current store no longer matches" do
    referral_code = create_referral_code!("STORE-REG-RETURN-MISMATCH")

    post stores_registrations_path, params: {
      store_registration: valid_registration_params(
        email: "store-registration-mismatch@example.com",
        referral_code: referral_code.code
      )
    }
    store = Store.order(:id).last
    assert_redirected_to edit_admin_store_registration_setup_path(store)

    complete_registration_setup(store)
    thanks_path = URI(response.location).request_uri

    registered_user = User.find_by!(email: "store-registration-mismatch@example.com")
    other_store = Store.create!(name: "Other Current Store")
    StoreMembership.create!(store: other_store, user: registered_user, membership_role: :admin)

    post admin_current_store_path, params: { store_id: other_store.id }
    get thanks_path

    assert_redirected_to edit_admin_store_path(other_store)
  end

  test "registration thanks rejects completion after store administrator access is revoked" do
    referral_code = create_referral_code!("STORE-REG-THANKS-REVOKED")
    email = "store-registration-thanks-revoked@example.com"

    post stores_registrations_path, params: {
      store_registration: valid_registration_params(
        email:,
        referral_code: referral_code.code
      )
    }
    store = Store.order(:id).last
    complete_registration_setup(store)
    StoreMembership.where(store:, user: User.find_by!(email:)).delete_all

    get stores_registration_thanks_path

    assert_redirected_to dashboard_path
    assert_nil @request.session[ApplicationController::STORE_REGISTRATION_COMPLETION_SESSION_KEY]
    assert_no_match(/window\.dataLayer\.push/, response.body)
  end

  private

  def create_referral_code!(code)
    ReferralCode.create!(
      code: code,
      enabled: true,
      expires_at: 1.day.from_now
    )
  end

  def valid_registration_params(overrides = {})
    {
      store_name: "登録テスト店舗",
      email: "store-registration-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password",
      referral_code: "STORE-REG-RETURN"
    }.merge(overrides)
  end

  def complete_registration_setup(store)
    patch admin_store_registration_setup_path(store), params: {
      store: { name: store.name }
    }
  end

  def contact_submission_params
    {
      store_contact_submission: {
        name: "Owner Name",
        store_name: "Sample Store",
        email: "owner@example.com",
        phone_number: "090-1234-5678",
        body: "Question about registration.",
        contactable_time: "Weekdays 10:00-18:00"
      }
    }
  end
end
