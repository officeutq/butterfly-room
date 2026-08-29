# frozen_string_literal: true

require "test_helper"

class ViewerPolicyTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Viewer Policy Store", published: true)
    @booth = Booth.create!(store: @store, name: "Viewer Policy Booth", status: :live)
    @cast = User.create!(email: "viewer-policy-cast@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "viewer-policy-customer@example.com", password: "password", role: :customer)
    @admin = User.create!(email: "viewer-policy-admin@example.com", password: "password", role: :store_admin)
    @stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/viewerPolicy"
    )
    @booth.update!(current_stream_session: @stream_session)
  end

  test "guest can view but cannot interact or ping presence" do
    policy = Authorization::ViewerPolicy.new(nil, @stream_session)

    assert policy.view_token?
    assert_not policy.create_comment?
    assert_not policy.create_drink_order?
    assert_not policy.ping_presence?
  end

  test "authenticated non-banned customer can view and interact" do
    policy = Authorization::ViewerPolicy.new(@customer, @stream_session)

    assert policy.view_token?
    assert policy.create_comment?
    assert policy.create_drink_order?
    assert policy.ping_presence?
  end

  test "banned customer remains unable to view or interact" do
    StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin
    )
    policy = Authorization::ViewerPolicy.new(@customer, @stream_session)

    assert_not policy.view_token?
    assert_not policy.create_comment?
    assert_not policy.create_drink_order?
    assert_not policy.ping_presence?
  end
end
