# frozen_string_literal: true

module StoreContactSubmissions
  class CreateService
    Result = Struct.new(:store_contact_submission, keyword_init: true)

    def initialize(attributes:)
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      store_contact_submission = StoreContactSubmission.new(
        @attributes.merge(source: StoreContactSubmission::SOURCE_STORES_LP)
      )
      store_contact_submission.save!
      enqueue_mail!(store_contact_submission)

      Result.new(store_contact_submission: store_contact_submission)
    end

    private

    def enqueue_mail!(store_contact_submission)
      enqueue_admin_notification!(store_contact_submission)

      StoreContactSubmissionMailer
        .with(store_contact_submission: store_contact_submission)
        .submitter_receipt
        .deliver_later
    end

    def enqueue_admin_notification!(store_contact_submission)
      return if StoreContactSubmissionMailer.admin_email.blank?

      StoreContactSubmissionMailer
        .with(store_contact_submission: store_contact_submission)
        .admin_notification
        .deliver_later
    end
  end
end
