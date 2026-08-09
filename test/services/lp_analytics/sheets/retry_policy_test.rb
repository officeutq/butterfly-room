# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Sheets::RetryPolicyTest < ActiveSupport::TestCase
  FakeApiError = Class.new(StandardError) do
    attr_reader :status_code

    def initialize(status_code)
      @status_code = status_code
      super("response body must not be logged")
    end
  end

  test "429と5xxを指数バックオフで有限回再試行する" do
    delays = []
    attempts = 0
    policy = LpAnalytics::Sheets::RetryPolicy.new(max_attempts: 3, base_delay: 0.25, sleeper: ->(delay) { delays << delay })

    result = policy.call do
      attempts += 1
      raise FakeApiError, 429 if attempts < 3

      :succeeded
    end

    assert_equal :succeeded, result
    assert_equal 3, attempts
    assert_equal [ 0.25, 0.5 ], delays
    assert LpAnalytics::Sheets::RetryPolicy.transient?(FakeApiError.new(503))
  end

  test "401と403は再試行しない" do
    [ 401, 403 ].each do |status|
      attempts = 0
      policy = LpAnalytics::Sheets::RetryPolicy.new(max_attempts: 3, sleeper: ->(*) { })

      assert_raises FakeApiError do
        policy.call do
          attempts += 1
          raise FakeApiError, status
        end
      end
      assert_equal 1, attempts
      refute LpAnalytics::Sheets::RetryPolicy.transient?(FakeApiError.new(status))
    end
  end

  test "timeoutを上限まで再試行する" do
    attempts = 0
    policy = LpAnalytics::Sheets::RetryPolicy.new(max_attempts: 2, sleeper: ->(*) { })

    assert_raises Timeout::Error do
      policy.call do
        attempts += 1
        raise Timeout::Error
      end
    end

    assert_equal 2, attempts
  end
end
