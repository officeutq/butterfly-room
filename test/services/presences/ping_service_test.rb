# frozen_string_literal: true

require "test_helper"

class Presences::PingServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "presence-ping-service")
    @cast = User.create!(email: "presence_ping_cast@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "presence_ping_customer@example.com", password: "password", role: :customer)
    @admin = User.create!(email: "presence_ping_admin@example.com", password: "password", role: :store_admin)
    @booth = Booth.create!(store: @store, name: "Booth", status: :live)
    @stream_session = StreamSession.create!(
      store: @store,
      booth: @booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/presence-ping"
    )
  end

  test "banned customer cannot ping presence at service layer" do
    StoreBan.create!(store: @store, customer_user: @customer, created_by_store_admin_user: @admin)

    assert_no_difference "Presence.count" do
      assert_raises(Presences::PingService::Forbidden) do
        Presences::PingService.new(
          stream_session: @stream_session,
          customer_user: @customer
        ).call!
      end
    end
  end

  test "revoked ban does not block presence ping" do
    StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      revoked_at: Time.current,
      revoked_by_user: @admin
    )

    assert_difference "Presence.count", 1 do
      Presences::PingService.new(
        stream_session: @stream_session,
        customer_user: @customer
      ).call!
    end
  end
end
