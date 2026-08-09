# frozen_string_literal: true

require "test_helper"

class StoreContactSubmissions::CreateServiceTest < ActiveSupport::TestCase
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

  test "creates submission and enqueues admin and submitter emails" do
    result = nil

    assert_difference -> { StoreContactSubmission.count }, +1 do
      assert_enqueued_emails 2 do
        result = StoreContactSubmissions::CreateService.new(
          attributes: valid_attributes
        ).call
      end
    end

    submission = result.store_contact_submission

    assert_equal "Owner Name", submission.name
    assert_equal "Sample Store", submission.store_name
    assert_equal "Girls Bar", submission.business_type
    assert_equal "owner@example.com", submission.email
    assert_equal "090-1234-5678", submission.phone_number
    assert_equal "Question about registration.", submission.body
    assert_equal "Weekdays 10:00-18:00", submission.contactable_time
    assert_equal StoreContactSubmission::SOURCE_STORES_LP, submission.source
  end

  test "does not enqueue admin email when admin address is not configured" do
    ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)

    assert_difference -> { StoreContactSubmission.count }, +1 do
      assert_enqueued_emails 1 do
        StoreContactSubmissions::CreateService.new(
          attributes: valid_attributes
        ).call
      end
    end
  end

  test "does not enqueue emails when submission is invalid" do
    visit = create_lp_analytics_visit

    assert_no_enqueued_emails do
      assert_no_difference [
        -> { StoreContactSubmission.count },
        -> { LpAnalytics::Event.count }
      ] do
        assert_raises(ActiveRecord::RecordInvalid) do
          StoreContactSubmissions::CreateService.new(
            attributes: valid_attributes.merge(name: ""),
            lp_analytics_visit: visit
          ).call
        end
      end
    end
  end

  test "counts a saved submission as complete even when mail enqueue fails" do
    visit = create_lp_analytics_visit
    service = StoreContactSubmissions::CreateService.new(
      attributes: valid_attributes,
      lp_analytics_visit: visit
    )
    service.define_singleton_method(:enqueue_mail!) { |_submission| raise "mail enqueue failed" }

    assert_difference [
      -> { StoreContactSubmission.count },
      -> { LpAnalytics::Event.where(event_type: "store_contact_complete").count }
    ], 1 do
      assert_raises(RuntimeError) { service.call }
    end

    submission = StoreContactSubmission.order(:id).last
    assert_equal visit, submission.lp_analytics_visit
    assert_equal submission, LpAnalytics::Event.order(:id).last.completion_record
  end

  private

  def valid_attributes
    {
      name: "Owner Name",
      store_name: "Sample Store",
      business_type: "Girls Bar",
      email: "owner@example.com",
      phone_number: "090-1234-5678",
      body: "Question about registration.",
      contactable_time: "Weekdays 10:00-18:00"
    }
  end

  def create_lp_analytics_visit
    now = Time.current
    LpAnalytics::Visit.create!(
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      device_type: "pc",
      started_at: now,
      last_activity_at: now
    )
  end

  def restore_admin_email_env
    if @previous_admin_email.nil?
      ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)
    else
      ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = @previous_admin_email
    end
  end
end
