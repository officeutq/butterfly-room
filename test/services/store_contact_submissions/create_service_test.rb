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
    assert_no_enqueued_emails do
      assert_no_difference -> { StoreContactSubmission.count } do
        assert_raises(ActiveRecord::RecordInvalid) do
          StoreContactSubmissions::CreateService.new(
            attributes: valid_attributes.merge(name: "")
          ).call
        end
      end
    end
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

  def restore_admin_email_env
    if @previous_admin_email.nil?
      ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)
    else
      ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = @previous_admin_email
    end
  end
end
