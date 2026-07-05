# frozen_string_literal: true

class StoreContactSubmissionMailer < ApplicationMailer
  ADMIN_EMAIL_ENV_KEY = "STORE_CONTACT_SUBMISSION_ADMIN_EMAIL"

  def self.admin_email
    ENV[ADMIN_EMAIL_ENV_KEY].presence
  end

  def admin_notification
    @store_contact_submission = params.fetch(:store_contact_submission)

    mail(
      to: self.class.admin_email,
      subject: "【Butterflyve】店舗向けLPからお問い合わせがありました"
    )
  end

  def submitter_receipt
    @store_contact_submission = params.fetch(:store_contact_submission)

    mail(
      to: @store_contact_submission.email,
      subject: "【Butterflyve】お問い合わせを受け付けました"
    )
  end
end
