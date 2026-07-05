# frozen_string_literal: true

require "test_helper"

class StoreContactSubmissionsTest < ActionDispatch::IntegrationTest
  test "guest can access new form" do
    get stores_contact_path

    assert_response :success
    assert_select "form[action=?].store-contact-submission-form", stores_contact_path
    assert_select "input[name='store_contact_submission[name]']"
    assert_select "input[name='store_contact_submission[store_name]']"
    assert_select "input[name='store_contact_submission[email]']"
    assert_select "input[name='store_contact_submission[phone_number]']"
    assert_select "textarea[name='store_contact_submission[body]']"
    assert_select "input[name='store_contact_submission[contactable_time]']"
  end

  test "form shows validation guidance and placeholders" do
    get stores_contact_path

    assert_response :success
    assert_select "label[for='store_contact_submission_name']", text: /お名前/
    assert_select "label[for='store_contact_submission_name'] .store-contact-submission-field-note",
      text: "（必須・#{StoreContactSubmission::NAME_MAX_LENGTH}文字以内）"
    assert_select "input[name='store_contact_submission[name]'][placeholder='例: 山田 太郎']"
    assert_select "label[for='store_contact_submission_store_name']", text: /店舗名/
    assert_select "label[for='store_contact_submission_store_name'] .store-contact-submission-field-note",
      text: "（必須・#{StoreContactSubmission::STORE_NAME_MAX_LENGTH}文字以内）"
    assert_select "input[name='store_contact_submission[store_name]'][placeholder='例: Butterflyve Bar 新宿店']"
    assert_select "label[for='store_contact_submission_email']", text: /メールアドレス/
    assert_select "label[for='store_contact_submission_email'] .store-contact-submission-field-note",
      text: "（必須・#{StoreContactSubmission::EMAIL_MAX_LENGTH}文字以内・メール形式）"
    assert_select "input[name='store_contact_submission[email]'][placeholder='例: owner@example.com']"
    assert_select "label[for='store_contact_submission_phone_number']", text: /電話番号/
    assert_select "label[for='store_contact_submission_phone_number'] .store-contact-submission-field-note",
      text: "（必須・#{StoreContactSubmission::PHONE_NUMBER_MAX_LENGTH}文字以内）"
    assert_select "input[name='store_contact_submission[phone_number]'][placeholder='例: 090-1234-5678']"
    assert_select ".form-text", text: "ハイフンあり・なし、先頭0、全角入力でも送信できます。"
    assert_select "label[for='store_contact_submission_body']", text: /お問い合わせ内容/
    assert_select "label[for='store_contact_submission_body'] .store-contact-submission-field-note",
      text: "（任意・5,000文字以内）"
    assert_select "textarea[name='store_contact_submission[body]'][placeholder='例: 導入時期や料金について相談したいです。']"
    assert_select "label[for='store_contact_submission_contactable_time']", text: /連絡可能時間帯/
    assert_select "label[for='store_contact_submission_contactable_time'] .store-contact-submission-field-note",
      text: "（任意・#{StoreContactSubmission::CONTACTABLE_TIME_MAX_LENGTH}文字以内）"
    assert_select "input[name='store_contact_submission[contactable_time]'][placeholder='例: 平日 10:00〜18:00']"
  end

  test "signed in user is redirected from new form" do
    sign_in create_user, scope: :user

    get stores_contact_path

    assert_redirected_to dashboard_path
  end

  test "signed in user cannot create submission" do
    sign_in create_user(email: "signed-in-create@example.com"), scope: :user

    assert_no_difference -> { StoreContactSubmission.count } do
      post stores_contact_path, params: submission_params
    end

    assert_redirected_to dashboard_path
  end

  test "guest can create submission with required attributes" do
    assert_difference -> { StoreContactSubmission.count }, +1 do
      assert_no_difference -> { SupportInquiry.count } do
        assert_no_difference -> { SupportInquiryMessage.count } do
          post stores_contact_path, params: submission_params
        end
      end
    end

    submission = StoreContactSubmission.order(:id).last

    assert_redirected_to stores_contact_path
    assert_equal "Owner Name", submission.name
    assert_equal "Sample Store", submission.store_name
    assert_equal "owner@example.com", submission.email
    assert_equal "090-1234-5678", submission.phone_number
    assert_equal "Question about registration.", submission.body
    assert_equal "Weekdays 10:00-18:00", submission.contactable_time
    assert_equal StoreContactSubmission::SOURCE_STORES_LP, submission.source
  end

  test "success message is displayed after create" do
    post stores_contact_path, params: submission_params
    follow_redirect!

    assert_response :success
    assert_select ".alert-success", text: "お問い合わせを受け付けました。内容を確認のうえ、担当者よりご連絡いたします。"
  end

  test "validation errors are displayed when required attributes are missing" do
    assert_no_difference -> { StoreContactSubmission.count } do
      post stores_contact_path, params: submission_params(
        name: "",
        store_name: "",
        email: "",
        phone_number: ""
      )
    end

    assert_response :unprocessable_entity
    assert_select ".alert-danger"
    assert_select "input[name='store_contact_submission[name]']"
    assert_select "input[name='store_contact_submission[store_name]']"
    assert_select "input[name='store_contact_submission[email]']"
    assert_select "input[name='store_contact_submission[phone_number]']"
  end

  test "body is optional when creating submission" do
    assert_difference -> { StoreContactSubmission.count }, +1 do
      post stores_contact_path, params: submission_params(body: "")
    end

    assert_redirected_to stores_contact_path
    assert_equal "", StoreContactSubmission.order(:id).last.body
  end

  test "contactable time is optional when creating submission" do
    assert_difference -> { StoreContactSubmission.count }, +1 do
      post stores_contact_path, params: submission_params(contactable_time: "")
    end

    assert_redirected_to stores_contact_path
    assert_equal "", StoreContactSubmission.order(:id).last.contactable_time
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
        email: "owner@example.com",
        phone_number: "090-1234-5678",
        body: "Question about registration.",
        contactable_time: "Weekdays 10:00-18:00"
      }.merge(overrides)
    }
  end
end
