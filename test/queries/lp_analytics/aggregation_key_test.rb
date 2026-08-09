# frozen_string_literal: true

require "test_helper"

class LpAnalytics::AggregationKeyTest < ActiveSupport::TestCase
  test "固定順序のcanonical JSONから安定したSHA-256を生成する" do
    dimensions = {
      aggregation_date: Date.new(2026, 8, 9),
      lp_identifier: "stores_lp_202607",
      traffic_source: "meta",
      utm_source: "facebook",
      utm_medium: "paid_social",
      utm_campaign: "campaign_a",
      utm_content: "creative_a"
    }

    first = LpAnalytics::AggregationKey.generate(**dimensions)
    second = LpAnalytics::AggregationKey.generate(**dimensions.to_a.reverse.to_h)

    assert_equal first, second
    assert_match(/\A[0-9a-f]{64}\z/, first)
  end

  test "単純な区切り文字連結なら衝突するdimensionを区別する" do
    common = {
      aggregation_date: Date.new(2026, 8, 9),
      lp_identifier: "stores_lp_202607",
      utm_medium: "",
      utm_campaign: "",
      utm_content: ""
    }

    first = LpAnalytics::AggregationKey.generate(**common, traffic_source: "a|b", utm_source: "c")
    second = LpAnalytics::AggregationKey.generate(**common, traffic_source: "a", utm_source: "b|c")

    refute_equal first, second
  end
end
