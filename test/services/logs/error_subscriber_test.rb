# frozen_string_literal: true

require "test_helper"

class Logs::ErrorSubscriberTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FailureJob < ActiveJob::Base
    def perform
      raise "job-secret"
    end
  end

  class RetryJob < ApplicationJob
    retry_on RuntimeError, wait: 1.second, attempts: 2

    def perform
      raise "retry-secret"
    end
  end

  setup do
    @request_id = SecureRandom.uuid
    @job_ids = []
  end

  teardown do
    ErrorLog.where(request_id: @request_id).delete_all
    ErrorLog.where(job_id: @job_ids).delete_all
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "Rails reports one error once and ignores expected client errors" do
    error = RuntimeError.new("private-message")
    assert_difference -> { ErrorLog.where(request_id: @request_id).count }, 1 do
      2.times { Rails.error.report(error, source: "application.action_dispatch", context: { request_id: @request_id }) }
      Rails.error.report(ActiveRecord::RecordNotFound.new, context: { request_id: @request_id })
    end
    assert_equal "web", ErrorLog.find_by!(request_id: @request_id).source
  end

  test "runner source is normalized" do
    Rails.error.report(RuntimeError.new, source: "application.runner.railties", context: { request_id: @request_id })
    assert_equal "runner", ErrorLog.find_by!(request_id: @request_id).source
  end

  test "all ActiveJob subclasses are reported without borrowing web identity" do
    job = FailureJob.new
    @job_ids << job.job_id
    ActiveSupport::ExecutionContext.set(log_source: "web", actor_user_id: 123, request_id: @request_id) do
      assert_raises(RuntimeError) { job.perform_now }
      assert_equal 123, ActiveSupport::ExecutionContext.to_h[:actor_user_id]
      Rails.error.report(RuntimeError.new, context: { request_id: @request_id })
    end
    entry = ErrorLog.where(job_id: job.job_id).sole
    assert_equal "job", entry.source
    assert_nil entry.actor_user_id
    assert_nil entry.request_id
    assert_equal FailureJob.name, entry.job_class
    assert_equal 1, entry.executions
    assert_not entry.handled
    assert_not_includes entry.to_json, "job-secret"
    assert_equal "web", ErrorLog.find_by!(request_id: @request_id).source
  end

  test "retry and terminal failure retain each attempt without duplicate reports" do
    job = RetryJob.new
    @job_ids << job.job_id
    job.perform_now
    assert_enqueued_jobs 1
    assert_raises(RuntimeError) { job.perform_now }
    entries = ErrorLog.where(job_id: job.job_id).order(:id).to_a
    assert_equal [ 1, 2 ], entries.map(&:executions)
    assert_equal [ true, false ], entries.map(&:handled)
  end
end
