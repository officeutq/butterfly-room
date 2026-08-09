# frozen_string_literal: true

require "test_helper"
require "fugit"
require "yaml"

class LpAnalyticsRecurringTest < ActiveSupport::TestCase
  test "productionで毎日02時20分JSTのrecurring Jobを定義する" do
    config = YAML.safe_load_file(Rails.root.join("config/recurring.yml"))
    task = config.fetch("production").fetch("lp_analytics_sheets_export")
    cron = Fugit::Cron.parse(task.fetch("schedule"))

    assert_equal "LpAnalytics::Sheets::ExportRecentDaysJob", task.fetch("class")
    assert_equal "default", task.fetch("queue")
    assert_equal [ 20 ], cron.minutes
    assert_equal [ 2 ], cron.hours
    assert_equal "Asia/Tokyo", cron.zone
  end
end
