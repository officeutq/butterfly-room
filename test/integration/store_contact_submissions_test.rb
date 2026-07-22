# frozen_string_literal: true

require "test_helper"

class StoreContactSubmissionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    clear_enqueued_jobs
    @previous_admin_email = ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY]
    ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = "store-contact-admin@example.com"
  end

  teardown do
    restore_admin_email_env
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "guest can access new form" do
    get stores_contact_path

    assert_response :success
    assert_select "form[action=?].store-contact-submission-form", stores_contact_path
    assert_select "a[href=?]", stores_lp_path
    assert_select "input[name='store_contact_submission[name]']"
    assert_select "input[name='store_contact_submission[store_name]']"
    assert_select "input[name='store_contact_submission[business_type]']"
    assert_select "input[name='store_contact_submission[email]']"
    assert_select "input[name='store_contact_submission[phone_number]']"
    assert_select "textarea[name='store_contact_submission[body]']"
    assert_select "input[name='store_contact_submission[contactable_time]']"
  end

  test "form keeps back link for current store LP" do
    get stores_contact_path(from: "stores_lp")

    assert_response :success
    assert_select "form[action=?].store-contact-submission-form", stores_contact_path(from: "stores_lp")
    assert_select "a[href=?]", stores_lp_path
    assert_select "a[href=?][data-turbo-prefetch]", stores_lp_path, count: 0
  end

  test "form keeps back link for store LP 202607" do
    get stores_contact_path(from: "stores_lp_202607")

    assert_response :success
    assert_select "form[action=?].store-contact-submission-form", stores_contact_path(from: "stores_lp_202607")
    assert_select "a[href=?]", stores_lp_202607_return_path
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
  end

  test "form keeps 202607 attribution in session without exposing utm params in action" do
    get stores_lp_202607_path, params: {
      ref: "1001",
      utm_source: " meta ",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607",
      utm_content: "flyer_a"
    }
    get stores_contact_path(from: "stores_lp_202607")

    assert_response :success
    assert_select "form[action=?].store-contact-submission-form",
      stores_contact_path(from: "stores_lp_202607")
    assert_no_match(/utm_source/, response.body)
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "1001", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
  end

  test "form falls back to current store LP when from is invalid" do
    get stores_contact_path(from: "https://example.com")

    assert_response :success
    assert_select "form[action=?].store-contact-submission-form", stores_contact_path
    assert_select "a[href=?]", stores_lp_path
    assert_no_match "https://example.com", response.body
  end

  test "form shows validation guidance and placeholders" do
    get stores_contact_path

    assert_response :success
    assert_select "label[for='store_contact_submission_name']", text: /お名前/
    assert_select "label[for='store_contact_submission_name'] .badge.store-contact-submission-field-badge",
      text: "必須"
    assert_select "input[name='store_contact_submission[name]'][placeholder='例: 山田 太郎']"
    assert_select "label[for='store_contact_submission_store_name']", text: /店舗名/
    assert_select "label[for='store_contact_submission_store_name'] .badge.store-contact-submission-field-badge",
      text: "必須"
    assert_select "input[name='store_contact_submission[store_name]'][placeholder='例: Butterflyve Bar 新宿店']"
    assert_select "label[for='store_contact_submission_business_type']", text: /業態/
    assert_select "label[for='store_contact_submission_business_type'] .badge.store-contact-submission-field-badge",
      text: "任意"
    assert_select "input[name='store_contact_submission[business_type]'][placeholder='例: ガールズバー']"
    assert_select "label[for='store_contact_submission_email']", text: /メールアドレス/
    assert_select "label[for='store_contact_submission_email'] .badge.store-contact-submission-field-badge",
      text: "必須"
    assert_select "input[name='store_contact_submission[email]'][placeholder='例: owner@example.com']"
    assert_select "label[for='store_contact_submission_phone_number']", text: /電話番号/
    assert_select "label[for='store_contact_submission_phone_number'] .badge.store-contact-submission-field-badge",
      text: "必須"
    assert_select "input[name='store_contact_submission[phone_number]'][placeholder='例: 090-1234-5678']"
    assert_select ".form-text", text: "ハイフンあり・なし、先頭0、全角入力でも送信できます。"
    assert_select "label[for='store_contact_submission_body']", text: /お問い合わせ内容/
    assert_select "label[for='store_contact_submission_body'] .badge.store-contact-submission-field-badge",
      text: "任意"
    assert_select "textarea[name='store_contact_submission[body]'][placeholder='例: 導入時期や料金について相談したいです。']"
    assert_select "label[for='store_contact_submission_contactable_time']", text: /連絡可能時間帯/
    assert_select "label[for='store_contact_submission_contactable_time'] .badge.store-contact-submission-field-badge",
      text: "任意"
    assert_select "input[name='store_contact_submission[contactable_time]'][placeholder='例: 平日 10:00〜18:00']"
  end

  test "signed in user is redirected from new form" do
    sign_in create_user, scope: :user

    get stores_contact_path

    assert_redirected_to dashboard_path
  end

  test "signed in user cannot create submission" do
    sign_in create_user(email: "signed-in-create@example.com"), scope: :user

    assert_no_enqueued_emails do
      assert_no_difference -> { StoreContactSubmission.count } do
        post stores_contact_path, params: submission_params
      end
    end

    assert_redirected_to dashboard_path
  end

  test "guest can create submission with required attributes" do
    assert_difference -> { StoreContactSubmission.count }, +1 do
      assert_no_difference -> { SupportInquiry.count } do
        assert_no_difference -> { SupportInquiryMessage.count } do
          assert_enqueued_emails 2 do
            post stores_contact_path, params: submission_params
          end
        end
      end
    end

    submission = StoreContactSubmission.order(:id).last

    assert_redirected_to stores_contact_thanks_path
    assert_equal "Owner Name", submission.name
    assert_equal "Sample Store", submission.store_name
    assert_equal "Girls Bar", submission.business_type
    assert_equal "owner@example.com", submission.email
    assert_equal "090-1234-5678", submission.phone_number
    assert_equal "Question about registration.", submission.body
    assert_equal "Weekdays 10:00-18:00", submission.contactable_time
    assert_equal StoreContactSubmission::SOURCE_STORES_LP, submission.source
  end

  test "create keeps store LP 202607 attribution in completion session and dataLayer" do
    get stores_lp_202607_path, params: {
      ref: "1001",
      utm_source: " meta ",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607"
    }

    assert_difference -> { StoreContactSubmission.count }, +1 do
      assert_enqueued_emails 2 do
        post stores_contact_path(from: "stores_lp_202607"), params: submission_params
      end
    end

    assert_redirected_to stores_contact_thanks_path(from: "stores_lp_202607")
    assert_equal(
      {
        "from" => "stores_lp_202607",
        "utm" => {
          "utm_source" => "meta",
          "utm_medium" => "paid_social",
          "utm_campaign" => "store_recruit_202607"
        },
        "completed" => true
      },
      @request.session[:store_contact_completion]
    )
    assert_equal StoreContactSubmission::SOURCE_STORES_LP, StoreContactSubmission.order(:id).last.source

    follow_redirect!

    assert_response :success
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
    assert_nil @request.session[:store_contact_completion]
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_equal "1001", @request.session[ApplicationController::STORE_LP_202607_REF_SESSION_KEY]
    assert_select "a[href=?]", stores_lp_202607_return_path, text: "店舗向けページへ戻る"
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
    refute_includes response.body, "Owner Name"
    refute_includes response.body, "owner@example.com"

    get stores_lp_202607_return_path, headers: { "X-Turbo-Request-ID" => "turbo-return" }
    assert_redirected_to stores_lp_202607_path(ref: "1001")

    get stores_lp_202607_path(ref: "1001"), headers: { "X-Turbo-Request-ID" => "turbo-lp-fetch" }
    assert_equal true, @request.session[ApplicationController::PRESERVE_STORE_LP_202607_ATTRIBUTION_ONCE_SESSION_KEY]
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]

    get stores_lp_202607_path(ref: "1001")
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_select "a[href=?]", stores_new_registration_path(ref: "1001", from: "stores_lp_202607"), minimum: 1
    assert_no_match(/utm_source/, response.body)
  end

  test "thanks page is displayed after create and cannot be reloaded" do
    post stores_contact_path, params: submission_params
    thanks_path = URI(response.location).request_uri

    follow_redirect!

    assert_response :success
    assert_select "h1", text: "お問い合わせを受け付けました"
    assert_select "a[href=?]", stores_lp_path, text: "店舗向けページへ戻る"
    assert_select "a[href=?][data-turbo-prefetch]", stores_lp_path, count: 0
    assert_equal [ { "event" => "store_contact_complete" } ], data_layer_events

    get thanks_path
    assert_redirected_to stores_contact_path
  end

  test "validation errors are displayed when required attributes are missing" do
    assert_no_enqueued_emails do
      assert_no_difference -> { StoreContactSubmission.count } do
        post stores_contact_path, params: submission_params(
          name: "",
          store_name: "",
          email: "",
          phone_number: ""
        )
      end
    end

    assert_response :unprocessable_entity
    assert_select ".alert-danger"
    assert_select "form[action=?].store-contact-submission-form", stores_contact_path
    assert_select "a[href=?]", stores_lp_path
    assert_select "input[name='store_contact_submission[name]']"
    assert_select "input[name='store_contact_submission[store_name]']"
    assert_select "input[name='store_contact_submission[business_type]']"
    assert_select "input[name='store_contact_submission[email]']"
    assert_select "input[name='store_contact_submission[phone_number]']"
  end

  test "validation errors keep store LP 202607 back link" do
    assert_no_enqueued_emails do
      assert_no_difference -> { StoreContactSubmission.count } do
        post stores_contact_path(from: "stores_lp_202607"), params: submission_params(
          name: "",
          store_name: "",
          email: "",
          phone_number: ""
        )
      end
    end

    assert_response :unprocessable_entity
    assert_select ".alert-danger"
    assert_select "form[action=?].store-contact-submission-form", stores_contact_path(from: "stores_lp_202607")
    assert_select "a[href=?]", stores_lp_202607_return_path
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
  end

  test "validation errors keep 202607 attribution session without exposing utm params" do
    get stores_lp_202607_path, params: {
      utm_source: "meta",
      utm_medium: "paid_social",
      utm_campaign: "store_recruit_202607"
    }

    assert_no_enqueued_emails do
      assert_no_difference -> { StoreContactSubmission.count } do
        post stores_contact_path(from: "stores_lp_202607"), params: submission_params(
          name: "",
          store_name: "",
          email: "",
          phone_number: ""
        )
      end
    end

    assert_response :unprocessable_entity
    assert_select "form[action=?].store-contact-submission-form",
      stores_contact_path(from: "stores_lp_202607")
    assert_select "a[href=?]", stores_lp_202607_return_path
    assert_select "a[href=?][data-turbo-prefetch=?][data-turbo=?]", stores_lp_202607_return_path, "false", "false"
    assert_equal "meta", @request.session[ApplicationController::STORE_LP_202607_ATTRIBUTION_SESSION_KEY]["utm_source"]
    assert_no_match(/utm_source/, response.body)
  end

  test "contact conversion event escapes unsafe utm values as JSON" do
    unsafe_content = "\"'</script><script>alert(1)</script>&"
    get stores_lp_202607_path, params: { utm_source: "meta", utm_content: unsafe_content }

    post stores_contact_path(from: "stores_lp_202607"), params: submission_params
    follow_redirect!

    assert_response :success
    assert_equal unsafe_content, data_layer_events.first["utm_content"]
    refute_includes response.body, "</script><script>alert(1)</script>"
  end

  test "thanks page redirects to form without completion session" do
    get stores_contact_thanks_path(from: "stores_lp_202607")

    assert_redirected_to stores_contact_path(from: "stores_lp_202607")
  end

  test "body is optional when creating submission" do
    assert_difference -> { StoreContactSubmission.count }, +1 do
      post stores_contact_path, params: submission_params(body: "")
    end

    assert_redirected_to stores_contact_thanks_path
    assert_equal "", StoreContactSubmission.order(:id).last.body
  end

  test "contactable time is optional when creating submission" do
    assert_difference -> { StoreContactSubmission.count }, +1 do
      post stores_contact_path, params: submission_params(contactable_time: "")
    end

    assert_redirected_to stores_contact_thanks_path
    assert_equal "", StoreContactSubmission.order(:id).last.contactable_time
  end

  test "business type is optional when creating submission" do
    assert_difference -> { StoreContactSubmission.count }, +1 do
      post stores_contact_path, params: submission_params(business_type: "")
    end

    assert_redirected_to stores_contact_thanks_path
    assert_equal "", StoreContactSubmission.order(:id).last.business_type
  end

  private

  def create_user(email: "store-contact-user@example.com")
    User.create!(email: email, password: "password", role: :customer)
  end

  def submission_params(overrides = {})
    {
      store_contact_submission: {
        name: "Owner Name",
        store_name: "Sample Store",
        business_type: "Girls Bar",
        email: "owner@example.com",
        phone_number: "090-1234-5678",
        body: "Question about registration.",
        contactable_time: "Weekdays 10:00-18:00"
      }.merge(overrides)
    }
  end

  def restore_admin_email_env
    if @previous_admin_email.nil?
      ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)
    else
      ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = @previous_admin_email
    end
  end
end
