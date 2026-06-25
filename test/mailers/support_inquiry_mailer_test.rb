# frozen_string_literal: true

require "test_helper"

class SupportInquiryMailerTest < ActionMailer::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    @customer = User.create!(
      email: "support_inquiry_mail_customer@example.com",
      password: "password",
      role: :customer,
      display_name: "Mail Customer"
    )
    @system_admin = User.create!(email: "support_inquiry_mail_admin@example.com", password: "password", role: :system_admin)
    @support_inquiry = SupportInquiries::CreateService.new(
      user: @customer,
      attributes: {
        category: "question",
        subject: "Mail subject",
        reply_email: "reply-destination@example.com"
      },
      message_body: "Initial message"
    ).call.support_inquiry
    @support_inquiry_message = @support_inquiry.support_inquiry_messages.create!(
      sender_user: @system_admin,
      sender_kind: :system_admin,
      body: "Mailer reply body"
    )
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "received email renders inquiry receipt" do
    first_message = @support_inquiry.support_inquiry_messages.order(:created_at, :id).first
    mail = SupportInquiryMailer
      .with(
        support_inquiry: @support_inquiry,
        support_inquiry_message: first_message
      )
      .received

    assert_equal [ "reply-destination@example.com" ], mail.to
    assert_equal "【Butterflyve】お問い合わせを受け付けました", mail.subject
    assert_match "Mail Customer", mail.text_part.body.decoded
    assert_match "お問い合わせを受け付けました", mail.text_part.body.decoded
    assert_match "Mail subject", mail.text_part.body.decoded
    assert_match @support_inquiry.category_label, mail.text_part.body.decoded
    assert_match "アプリ内のお問い合わせ詳細から確認・返信できます", mail.text_part.body.decoded
    assert_match "このメールへの直接返信ではなく", mail.text_part.body.decoded
    assert_match "/support/inquiries/#{@support_inquiry.id}", mail.text_part.body.decoded
    assert_match "お問い合わせを受け付けました", mail.html_part.body.decoded
  end

  test "reply email renders inquiry reply" do
    mail = SupportInquiryMailer
      .with(
        support_inquiry: @support_inquiry,
        support_inquiry_message: @support_inquiry_message
      )
      .reply

    assert_equal [ "reply-destination@example.com" ], mail.to
    assert_equal "【Butterflyve】お問い合わせに返信がありました", mail.subject
    assert_match "Mail Customer", mail.text_part.body.decoded
    assert_match "Mail subject", mail.text_part.body.decoded
    assert_match "Mailer reply body", mail.text_part.body.decoded
    assert_match "アプリ内のお問い合わせ画面から返信してください", mail.text_part.body.decoded
    assert_match "/support/inquiries/#{@support_inquiry.id}", mail.text_part.body.decoded
    assert_match "Mailer reply body", mail.html_part.body.decoded
  end
end
