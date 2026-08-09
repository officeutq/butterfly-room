# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Visits::ResolveServiceTest < ActiveSupport::TestCase
  BASE_TIME = Time.zone.parse("2026-08-09 12:00:00")
  BASE_TRAFFIC = {
    traffic_source: "meta",
    utm_source: "facebook",
    utm_medium: "paid_social",
    utm_campaign: "campaign_a",
    utm_content: "creative_a",
    referral_code: "1001"
  }.freeze
  USER_AGENT = "Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1"

  test "初回LP流入で匿名訪問を作成する" do
    visit = nil

    assert_difference "LpAnalytics::Visit.count", 1 do
      visit = resolve(now: BASE_TIME)
    end

    assert_match LpAnalytics::Event::UUID_PATTERN, visit.public_id
    assert_equal LpAnalytics::Configuration::STORE_LP_202607, visit.lp_identifier
    assert_equal BASE_TRAFFIC, visit.traffic_attributes
    assert_equal "smartphone", visit.device_type
    assert_equal "safari", visit.browser_type
    assert_equal BASE_TIME, visit.started_at
    assert_equal BASE_TIME, visit.last_activity_at
  end

  test "30分以内で同じ流入情報なら同じ訪問を継続する" do
    first_visit = resolve(now: BASE_TIME)
    continued_visit = nil

    assert_no_difference "LpAnalytics::Visit.count" do
      continued_visit = resolve(public_id: first_visit.public_id, now: BASE_TIME + 29.minutes)
    end

    assert_equal first_visit.id, continued_visit.id
    assert_equal BASE_TIME + 29.minutes, continued_visit.last_activity_at
  end

  test "不正な公開用UUIDがsessionにあっても新しい訪問を安全に作成する" do
    visit = nil

    assert_difference "LpAnalytics::Visit.count", 1 do
      visit = resolve(public_id: "invalid-public-id", now: BASE_TIME)
    end

    assert_match LpAnalytics::Visit::UUID_PATTERN, visit.public_id
  end

  test "最後の操作から30分経過した場合は新しい訪問にする" do
    first_visit = resolve(now: BASE_TIME)
    next_visit = nil

    assert_difference "LpAnalytics::Visit.count", 1 do
      next_visit = resolve(public_id: first_visit.public_id, now: BASE_TIME + 30.minutes)
    end

    refute_equal first_visit.id, next_visit.id
  end

  test "流入情報のいずれかが変わった場合は新しい訪問にする" do
    first_visit = resolve(now: BASE_TIME)

    LpAnalytics::Visits::ResolveService::TRAFFIC_KEYS.each_with_index do |key, index|
      changed_traffic = BASE_TRAFFIC.merge(key => "changed_#{key}")
      next_visit = resolve(
        public_id: first_visit.public_id,
        traffic: changed_traffic,
        now: BASE_TIME + index.minutes
      )

      refute_equal first_visit.id, next_visit.id, key.to_s
      assert_equal changed_traffic, next_visit.traffic_attributes
    end
  end

  test "LPへのreturnでは既存流入情報を維持する" do
    first_visit = resolve(now: BASE_TIME)
    continued_visit = resolve(
      public_id: first_visit.public_id,
      traffic: { referral_code: BASE_TRAFFIC[:referral_code] },
      preserve_existing_traffic: true,
      now: BASE_TIME + 1.minute
    )

    assert_equal first_visit.id, continued_visit.id
    assert_equal BASE_TRAFFIC, continued_visit.traffic_attributes
  end

  test "流入値をtrimし上限長を超える部分は保存しない" do
    visit = resolve(
      traffic: BASE_TRAFFIC.merge(utm_content: "  #{'a' * 120}  "),
      now: BASE_TIME
    )

    assert_equal "a" * 100, visit.utm_content
  end

  test "raw User-AgentやIPや個人情報の列を持たず正規化した端末情報だけ保存する" do
    raw_user_agent = "Mozilla/5.0 (iPad) AppleWebKit/605.1.15 Version/18.0 Safari/604.1"
    visit = resolve(user_agent: raw_user_agent, now: BASE_TIME)

    assert_equal "tablet", visit.device_type
    assert_equal "safari", visit.browser_type
    refute_includes visit.attributes.values, raw_user_agent
    %w[user_agent raw_user_agent ip_address name email phone_number].each do |column|
      refute_includes LpAnalytics::Visit.column_names, column
    end
  end

  test "LP設定の追加だけで訪問解決Serviceを他LPにも利用できる" do
    configuration = Object.new
    configuration.define_singleton_method(:supported_lp?) { |identifier| identifier == "future_lp" }
    visit = resolve(lp_identifier: "future_lp", configuration: configuration, now: BASE_TIME)

    assert_equal "future_lp", visit.lp_identifier
  end

  private

  def resolve(
    public_id: nil,
    lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
    traffic: BASE_TRAFFIC,
    user_agent: USER_AGENT,
    preserve_existing_traffic: false,
    configuration: LpAnalytics::Configuration,
    now:
  )
    LpAnalytics::Visits::ResolveService.new(
      public_id: public_id,
      lp_identifier: lp_identifier,
      traffic_attributes: traffic,
      user_agent: user_agent,
      preserve_existing_traffic: preserve_existing_traffic,
      configuration: configuration,
      now: now
    ).call
  end
end
