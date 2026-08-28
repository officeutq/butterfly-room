# frozen_string_literal: true

module StoreContactSubmissions
  class ResendAdminNotificationService
    class AdminEmailNotConfiguredError < StandardError; end

    def initialize(store_contact_submission:)
      @store_contact_submission = store_contact_submission
    end

    def call
      raise AdminEmailNotConfiguredError if StoreContactSubmissionMailer.admin_email.blank?

      StoreContactSubmissionMailer
        .with(store_contact_submission: @store_contact_submission)
        .admin_notification
        .deliver_later
    end
  end
end
