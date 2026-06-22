# frozen_string_literal: true

require "test_helper"

class Admin::StoreBans::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "store-ban-create-service")
    @other_store = Store.create!(name: "store-ban-create-service-other")
    @admin = User.create!(email: "store_ban_create_admin@example.com", password: "password", role: :store_admin)
    @customer = User.create!(email: "store_ban_create_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "store_ban_create_cast@example.com", password: "password", role: :cast)

    @booth = Booth.create!(store: @store, name: "Booth", status: :live)
    @stream_session = StreamSession.create!(
      store: @store,
      booth: @booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/store-ban-create"
    )
    @comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "reported"
    )
  end

  test "creates active store ban with source comment" do
    result = nil

    assert_difference "StoreBan.count", 1 do
      result = Admin::StoreBans::CreateService.new(
        store: @store,
        customer_user: @customer,
        actor: @admin,
        reason: "reason",
        source_comment: @comment
      ).call
    end

    assert result.created
    assert_equal @comment, result.store_ban.source_comment
    assert_equal "reason", result.store_ban.reason
  end

  test "already active ban is success without duplicate" do
    existing = StoreBan.create!(store: @store, customer_user: @customer, created_by_store_admin_user: @admin)

    assert_no_difference "StoreBan.count" do
      result = Admin::StoreBans::CreateService.new(
        store: @store,
        customer_user: @customer,
        actor: @admin
      ).call

      assert_not result.created
      assert_equal existing, result.store_ban
    end
  end

  test "revoked ban allows re-ban" do
    StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      revoked_at: Time.current,
      revoked_by_user: @admin
    )

    assert_difference "StoreBan.count", 1 do
      result = Admin::StoreBans::CreateService.new(
        store: @store,
        customer_user: @customer,
        actor: @admin
      ).call

      assert result.created
      assert result.store_ban.active?
    end
  end

  test "rejects non customer target" do
    assert_raises(Admin::StoreBans::CreateService::UnsupportedCustomerError) do
      Admin::StoreBans::CreateService.new(
        store: @store,
        customer_user: @cast,
        actor: @admin
      ).call
    end
  end

  test "rejects source comment from other store" do
    assert_raises(Admin::StoreBans::CreateService::SourceCommentStoreMismatchError) do
      Admin::StoreBans::CreateService.new(
        store: @other_store,
        customer_user: @customer,
        actor: @admin,
        source_comment: @comment
      ).call
    end
  end
end
