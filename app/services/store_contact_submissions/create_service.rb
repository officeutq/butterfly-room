# frozen_string_literal: true

module StoreContactSubmissions
  class CreateService
    Result = Struct.new(:store_contact_submission, keyword_init: true)

    def initialize(attributes:, lp_analytics_visit: nil)
      @attributes = attributes.to_h.symbolize_keys
      @lp_analytics_visit = lp_analytics_visit
    end

    def call
      store_contact_submission = StoreContactSubmission.new(
        @attributes.merge(
          source: StoreContactSubmission::SOURCE_STORES_LP,
          lp_analytics_visit: @lp_analytics_visit
        )
      )
      store_contact_submission.save!
      record_lp_analytics_completion(store_contact_submission)
      enqueue_mail!(store_contact_submission)

      Result.new(store_contact_submission: store_contact_submission)
    end

    private

    def record_lp_analytics_completion(store_contact_submission)
      return if @lp_analytics_visit.blank?

      LpAnalytics::Completions::RecordService.new(
        visit: @lp_analytics_visit,
        event_type: "store_contact_complete",
        completion_record: store_contact_submission
      ).call
    end

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
