# frozen_string_literal: true

require "test_helper"

class StoreContactSubmissionMailerTest < ActionMailer::TestCase
  setup do
    @previous_admin_email = ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY]
    ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = "store-contact-admin@example.com"
    @store_contact_submission = StoreContactSubmission.create!(
      name: "Owner Name",
      store_name: "Sample Store",
      email: "owner@example.com",
      phone_number: "090-1234-5678",
      body: "Question about registration.",
      contactable_time: "Weekdays 10:00-18:00"
    )
  end

  teardown do
    restore_admin_email_env
  end

  test "admin notification is sent to env address and includes submission content" do
    mail = StoreContactSubmissionMailer
      .with(store_contact_submission: @store_contact_submission)
      .admin_notification

    assert_equal [ "store-contact-admin@example.com" ], mail.to
    assert_equal "【Butterflyve】店舗向けLPからお問い合わせがありました", mail.subject
    assert_match "店舗向けLPからお問い合わせがありました。", mail.text_part.body.decoded
    assert_match "Owner Name", mail.text_part.body.decoded
    assert_match "Sample Store", mail.text_part.body.decoded
    assert_match "owner@example.com", mail.text_part.body.decoded
    assert_match "090-1234-5678", mail.text_part.body.decoded
    assert_match "Weekdays 10:00-18:00", mail.text_part.body.decoded
    assert_match "Question about registration.", mail.text_part.body.decoded
    assert_match I18n.l(@store_contact_submission.created_at), mail.text_part.body.decoded
    assert_match "Question about registration.", mail.html_part.body.decoded
  end

  test "submitter receipt is sent to submission email and includes receipt message" do
    mail = StoreContactSubmissionMailer
      .with(store_contact_submission: @store_contact_submission)
      .submitter_receipt

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "【Butterflyve】お問い合わせを受け付けました", mail.subject
    assert_match "Owner Name", mail.text_part.body.decoded
    assert_match "お問い合わせを受け付けました。", mail.text_part.body.decoded
    assert_match "内容を確認のうえ、担当者よりご連絡いたします。", mail.text_part.body.decoded
    assert_match "入力内容の控え", mail.text_part.body.decoded
    assert_match "Sample Store", mail.text_part.body.decoded
    assert_match "owner@example.com", mail.text_part.body.decoded
    assert_match "090-1234-5678", mail.text_part.body.decoded
    assert_match "Weekdays 10:00-18:00", mail.text_part.body.decoded
    assert_match "Question about registration.", mail.text_part.body.decoded
    assert_match "お問い合わせを受け付けました。", mail.html_part.body.decoded
  end

  test "admin email is read from environment variable" do
    ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = "another-admin@example.com"

    mail = StoreContactSubmissionMailer
      .with(store_contact_submission: @store_contact_submission)
      .admin_notification

    assert_equal [ "another-admin@example.com" ], mail.to
  end

  private

  def restore_admin_email_env
    if @previous_admin_email.nil?
      ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)
    else
      ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = @previous_admin_email
    end
  end
end
