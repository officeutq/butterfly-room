# frozen_string_literal: true

require "test_helper"

class AdminCastMetricsTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  ZONE = "Asia/Tokyo"

  setup do
    @store = Store.create!(name: "cast metrics admin store")
    @store_admin = User.create!(email: "admin-cast-metrics@example.com", password: "password", role: :store_admin)
    @cast = User.create!(email: "admin-cast-metrics-cast@example.com", password: "password", role: :cast)

    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
    @booth = Booth.create!(store: @store, name: "cast metrics booth", status: :offline)
    BoothCast.create!(booth: @booth, cast_user: @cast)
  end

  test "initial view keeps previous month selected when first metrics are in current month" do
    Time.use_zone(ZONE) do
      travel_to Time.zone.local(2026, 7, 26, 12, 0, 0) do
        create_stream_session!(
          broadcast_started_at: Time.zone.local(2026, 7, 5, 20, 0, 0),
          ended_at: Time.zone.local(2026, 7, 5, 20, 30, 0)
        )

        sign_in @store_admin, scope: :user
        select_current_store(@store)

        get admin_cast_metrics_path

        assert_response :success
        assert_select "select[name='month'] option[value='2026-06'][selected]", count: 1
        assert_select "select[name='month'] option[value='2026-07']", count: 1
        assert_select ".referral-code-card", count: 0

        get admin_cast_metrics_path(month: "2026-07")

        assert_response :success
        assert_select "select[name='month'] option[value='2026-07'][selected]", count: 1
        assert_select ".referral-code-card", count: 1
      end
    end
  end

  private

  def select_current_store(store)
    post admin_current_store_path, params: { store_id: store.id }
    follow_redirect!
    assert_response :success
  end

  def create_stream_session!(broadcast_started_at:, ended_at:)
    StreamSession.create!(
      store: @store,
      booth: @booth,
      started_by_cast_user: @cast,
      status: :ended,
      started_at: broadcast_started_at,
      broadcast_started_at: broadcast_started_at,
      ended_at: ended_at
    )
  end
end
