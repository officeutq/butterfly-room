# frozen_string_literal: true

require "test_helper"
require "stringio"

module Stores
  class CompleteRegistrationSetupTest < ActiveSupport::TestCase
    test "publishes the store and records LP analytics completion after saving" do
      visit = create_visit
      store = Store.create!(name: "設定前店舗", published: false, lp_analytics_visit: visit)

      assert_difference -> { completion_events.count }, 1 do
        CompleteRegistrationSetup.new(
          store:,
          attributes: { name: "設定後店舗", description: "初回設定完了" }
        ).call
      end

      store.reload
      assert store.published?
      assert_equal "設定後店舗", store.name
      assert_equal "初回設定完了", store.description
      assert_equal store, completion_events.last.completion_record
      assert_equal visit, completion_events.last.visit
    end

    test "does not record completion or publish when the store update fails" do
      visit = create_visit
      store = Store.create!(name: "更新失敗店舗", published: false, lp_analytics_visit: visit)

      assert_no_difference -> { completion_events.count } do
        assert_raises ActiveRecord::RecordInvalid do
          CompleteRegistrationSetup.new(store:, attributes: { name: "" }).call
        end
      end

      store.reload
      assert_not store.published?
      assert_equal "更新失敗店舗", store.name
    end

    test "forces published and ignores protected attributes supplied by a caller" do
      store = Store.create!(name: "保護属性店舗", published: false, sales_support_company: false)

      CompleteRegistrationSetup.new(
        store:,
        attributes: { name: store.name, published: false, sales_support_company: true }
      ).call

      store.reload
      assert store.published?
      assert_not store.sales_support_company?
    end

    test "keeps the completed store when analytics recording unexpectedly raises" do
      visit = create_visit
      store = Store.create!(name: "分析失敗店舗", published: false, lp_analytics_visit: visit)
      logger_output = StringIO.new
      logger = ActiveSupport::Logger.new(logger_output)
      failing_completion_service = Class.new do
        def initialize(**); end

        def call
          raise IOError, "analytics unavailable"
        end
      end

      CompleteRegistrationSetup.new(
        store:,
        attributes: { description: "保存済み" },
        completion_service: failing_completion_service,
        logger:
      ).call

      store.reload
      assert store.published?
      assert_equal "保存済み", store.description
      assert_equal 0, completion_events.count
      assert_includes logger_output.string, "store_registration_completion_record_failed"
      assert_includes logger_output.string, "IOError"
      assert_not_includes logger_output.string, "analytics unavailable"
    end

    test "allows completion without an LP analytics visit" do
      store = Store.create!(name: "直接登録店舗", published: false)

      assert_no_difference -> { completion_events.count } do
        CompleteRegistrationSetup.new(store:, attributes: {}).call
      end

      assert store.reload.published?
    end

    private

    def completion_events
      LpAnalytics::Event.where(event_type: "store_registration_complete")
    end

    def create_visit
      now = Time.current
      LpAnalytics::Visit.create!(
        lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
        device_type: "pc",
        started_at: now,
        last_activity_at: now
      )
    end
  end
end
