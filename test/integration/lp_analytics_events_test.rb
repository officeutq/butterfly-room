# frozen_string_literal: true

require "test_helper"

class LpAnalyticsEventsTest < ActionDispatch::IntegrationTest
  LP_PATH_PARAMS = {
    from: "meta",
    utm_source: "facebook",
    utm_medium: "paid_social",
    utm_campaign: "campaign_a",
    utm_content: "creative_a",
    ref: "1001"
  }.freeze

  test "LP初回表示で訪問を作り同一流入のreloadでは継続する" do
    assert_difference "LpAnalytics::Visit.count", 1 do
      get stores_lp_202607_path, params: LP_PATH_PARAMS
    end

    assert_response :success
    visit = LpAnalytics::Visit.order(:id).last
    assert_equal visit.public_id,
      @request.session[ApplicationController::LP_ANALYTICS_VISIT_PUBLIC_ID_SESSION_KEY]

    assert_no_difference "LpAnalytics::Visit.count" do
      get stores_lp_202607_path, params: LP_PATH_PARAMS
    end

    assert_equal visit.id, LpAnalytics::Visit.find_by!(
      public_id: @request.session[ApplicationController::LP_ANALYTICS_VISIT_PUBLIC_ID_SESSION_KEY]
    ).id
  end

  test "30分経過後または流入情報変更後のLP表示は新しい訪問にする" do
    get stores_lp_202607_path, params: LP_PATH_PARAMS
    first_visit = LpAnalytics::Visit.order(:id).last

    travel_to first_visit.last_activity_at + 31.minutes do
      assert_difference "LpAnalytics::Visit.count", 1 do
        get stores_lp_202607_path, params: LP_PATH_PARAMS
      end
    end

    second_visit = LpAnalytics::Visit.order(:id).last
    refute_equal first_visit.id, second_visit.id

    assert_difference "LpAnalytics::Visit.count", 1 do
      get stores_lp_202607_path, params: LP_PATH_PARAMS.merge(utm_content: "creative_b")
    end

    refute_equal second_visit.id, LpAnalytics::Visit.order(:id).last.id
  end

  test "LPのreturnでは匿名訪問と流入情報を維持する" do
    get stores_lp_202607_path, params: LP_PATH_PARAMS.except(:from)
    visit = LpAnalytics::Visit.order(:id).last

    get stores_lp_202607_return_path
    follow_redirect!

    assert_response :success
    assert_equal visit.public_id,
      @request.session[ApplicationController::LP_ANALYTICS_VISIT_PUBLIC_ID_SESSION_KEY]
    assert_equal "facebook", visit.reload.utm_source
  end

  test "sessionの匿名訪問へブラウザイベントを記録する" do
    get stores_lp_202607_path, params: LP_PATH_PARAMS
    event_id = SecureRandom.uuid

    assert_difference "LpAnalytics::Event.count", 1 do
      post_event(
        event_id: event_id,
        event_type: "section_reached",
        event_value: "PRICING",
        metadata: { viewport_type: "pc" }
      )
    end

    assert_response :created
    assert_equal({ "recorded" => true, "duplicate" => false }, response.parsed_body)
    event = LpAnalytics::Event.order(:id).last
    assert_equal "PRICING", event.event_value
    assert_equal "stores_lp_202607", event.lp_identifier
  end

  test "同じブラウザイベントUUIDの再送は成功扱いで重複保存しない" do
    get stores_lp_202607_path
    event_id = SecureRandom.uuid
    attributes = {
      event_id: event_id,
      event_type: "cta_clicked",
      event_value: "hero_registration"
    }

    post_event(**attributes)
    assert_response :created

    assert_no_difference "LpAnalytics::Event.count" do
      post_event(**attributes)
    end

    assert_response :ok
    assert_equal({ "recorded" => true, "duplicate" => true }, response.parsed_body)
  end

  test "session内で許可された過去の訪問IDへ複数tabのイベントを記録できる" do
    get stores_lp_202607_path, params: { utm_content: "creative_a" }
    first_visit = LpAnalytics::Visit.order(:id).last
    get stores_lp_202607_path, params: { utm_content: "creative_b" }
    second_visit = LpAnalytics::Visit.order(:id).last

    refute_equal first_visit.id, second_visit.id

    assert_difference -> { first_visit.events.count }, 1 do
      post_event(
        visit_id: first_visit.public_id,
        event_id: SecureRandom.uuid,
        event_type: "cta_clicked",
        event_value: "hero_registration"
      )
    end

    assert_response :created
    assert_equal first_visit.id, LpAnalytics::Event.order(:id).last.lp_analytics_visit_id
  end

  test "session内で許可されていない訪問IDへのイベントを拒否する" do
    get stores_lp_202607_path

    assert_no_difference "LpAnalytics::Event.count" do
      post_event(
        visit_id: SecureRandom.uuid,
        event_id: SecureRandom.uuid,
        event_type: "lp_view"
      )
    end

    assert_response :unprocessable_entity
  end

  test "訪問sessionがない場合と未許可payloadは保存しない" do
    assert_no_difference "LpAnalytics::Event.count" do
      post_event(event_id: SecureRandom.uuid, event_type: "lp_view")
    end
    assert_response :unprocessable_entity

    get stores_lp_202607_path

    assert_no_difference "LpAnalytics::Event.count" do
      post_event(
        event_id: SecureRandom.uuid,
        event_type: "lp_view",
        metadata: { email: "owner@example.com" }
      )
    end
    assert_response :unprocessable_entity
  end

  test "完了イベントをブラウザAPIから記録できない" do
    get stores_lp_202607_path

    assert_no_difference "LpAnalytics::Event.count" do
      %w[store_registration_complete store_contact_complete].each do |event_type|
        post_event(event_id: SecureRandom.uuid, event_type: event_type)
        assert_response :unprocessable_entity
      end
    end
  end

  test "異なるoriginと上限超過requestを拒否する" do
    get stores_lp_202607_path

    assert_no_difference "LpAnalytics::Event.count" do
      post_event(
        event_id: SecureRandom.uuid,
        event_type: "lp_view",
        origin: "https://attacker.example"
      )
    end
    assert_response :forbidden

    oversized_payload = {
      lp_analytics_event: {
        event_id: SecureRandom.uuid,
        event_type: "lp_view",
        metadata: { viewport_type: "x" * 20.kilobytes }
      }
    }
    post lp_analytics_events_path,
      params: oversized_payload.to_json,
      headers: json_headers

    assert_response 413
  end

  test "イベントAPIはCSRF保護を無効化していない" do
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get stores_lp_202607_path

    assert_no_difference "LpAnalytics::Event.count" do
      post_event(event_id: SecureRandom.uuid, event_type: "lp_view")
    end

    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
  end

  test "LP行動payload全体をparameter filterの対象にする" do
    filtered = ActiveSupport::ParameterFilter
      .new(Rails.application.config.filter_parameters)
      .filter(
        "lp_analytics_visit_id" => SecureRandom.uuid,
        "lp_analytics_event" => {
          "event_type" => "invalid-owner@example.com",
          "metadata" => { "body" => "private text" }
        },
        "store_registration" => {
          "store_name" => "Private Store",
          "email" => "registration-owner@example.com",
          "password" => "private password"
        },
        "store_contact_submission" => {
          "name" => "Private Owner",
          "store_name" => "Private Store",
          "email" => "contact-owner@example.com",
          "phone_number" => "090-1234-5678",
          "body" => "private inquiry"
        }
      )

    assert_equal "[FILTERED]", filtered["lp_analytics_event"]
    assert_equal "[FILTERED]", filtered["lp_analytics_visit_id"]
    assert_equal "[FILTERED]", filtered["store_registration"]
    assert_equal "[FILTERED]", filtered["store_contact_submission"]
  end

  private

  def post_event(
    event_id:,
    event_type:,
    visit_id: nil,
    event_value: nil,
    metadata: {},
    origin: "http://www.example.com"
  )
    post lp_analytics_events_path,
      params: {
        lp_analytics_event: {
          visit_id: visit_id,
          event_id: event_id,
          event_type: event_type,
          event_value: event_value,
          metadata: metadata
        }
      }.to_json,
      headers: json_headers.merge("Origin" => origin)
  end

  def json_headers
    { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
  end
end
