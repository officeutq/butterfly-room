# frozen_string_literal: true

require "test_helper"

class StoreContactSubmissions::ResendAdminNotificationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
    ActionMailer::Base.deliveries.clear

    @previous_admin_email = ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY]
    ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = "old-admin@example.com"
    @store_contact_submission = StoreContactSubmission.create!(
      name: "Owner Name",
      store_name: "Sample Store",
      email: "owner@example.com",
      phone_number: "090-1234-5678"
    )
  end

  teardown do
    restore_admin_email_env
    clear_enqueued_jobs
    clear_performed_jobs
    ActionMailer::Base.deliveries.clear
  end

  test "enqueues only the admin notification" do
    assert_enqueued_emails 1 do
      assert_enqueued_email_with(
        StoreContactSubmissionMailer,
        :admin_notification,
        params: { store_contact_submission: @store_contact_submission }
      ) do
        service.call
      end
    end
  end

  test "uses the current admin address when the queued mail is performed" do
    service.call
    ENV[StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY] = "new-admin@example.com"

    perform_enqueued_jobs

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal [ "new-admin@example.com" ], ActionMailer::Base.deliveries.last.to
  end

  test "does not enqueue mail when the admin address is not configured" do
    ENV.delete(StoreContactSubmissionMailer::ADMIN_EMAIL_ENV_KEY)

    assert_no_enqueued_emails do
      assert_raises(
        StoreContactSubmissions::ResendAdminNotificationService::AdminEmailNotConfiguredError
      ) { service.call }
    end
  end

  test "allows the same submission to be enqueued again" do
    assert_enqueued_emails 2 do
      service.call
      service.call
    end
  end

  private

  def service
    StoreContactSubmissions::ResendAdminNotificationService.new(
      store_contact_submission: @store_contact_submission
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
