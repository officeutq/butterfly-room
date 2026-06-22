# frozen_string_literal: true

require "test_helper"

class Admin::CommentReports::RevokeBanServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "revoke-ban-service-store")
    @other_store = Store.create!(name: "revoke-ban-service-other-store")

    @admin = User.create!(email: "revoke_ban_service_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "revoke_ban_service_system@example.com", password: "password", role: :system_admin)
    @cast = User.create!(email: "revoke_ban_service_cast@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "revoke_ban_service_customer@example.com", password: "password", role: :customer)
    @other_customer = User.create!(email: "revoke_ban_service_other_customer@example.com", password: "password", role: :customer)

    @booth = Booth.create!(store: @store, name: "Booth", status: :live)
    @stream_session = StreamSession.create!(
      store: @store,
      booth: @booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/revoke-ban-service"
    )
    @booth.update!(current_stream_session: @stream_session)

    @comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "reported comment"
    )
  end

  test "revokes comment-origin active ban without deleting it" do
    report = create_report(comment: @comment, status: :resolved)
    store_ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      source_comment: @comment
    )

    assert_no_difference "StoreBan.count" do
      result = Admin::CommentReports::RevokeBanService.new(
        comment: @comment,
        actor: @admin,
        current_store: @store
      ).call

      assert result.revoked
    end

    assert store_ban.reload.revoked?
    assert_equal @admin, store_ban.revoked_by_user
    assert_equal "comment_report_revoke", store_ban.revocation_reason
    assert_equal "resolved", report.reload.status
  end

  test "does not revoke manual ban without source comment" do
    store_ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @system_admin
    )

    assert_raises(Admin::CommentReports::RevokeBanService::RevokeTargetNotFoundError) do
      Admin::CommentReports::RevokeBanService.new(
        comment: @comment,
        actor: @admin,
        current_store: @store
      ).call
    end

    assert store_ban.reload.active?
  end

  test "revokes comment-origin ban from another source comment for same customer" do
    other_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "other reported comment"
    )
    store_ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      source_comment: other_comment
    )

    assert_no_difference "StoreBan.count" do
      result = Admin::CommentReports::RevokeBanService.new(
        comment: @comment,
        actor: @admin,
        current_store: @store
      ).call

      assert result.revoked
    end

    assert store_ban.reload.revoked?
  end

  test "does not revoke ban when source comment belongs to another customer" do
    other_source_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @other_customer,
      kind: Comment::KIND_CHAT,
      body: "other customer source comment"
    )
    store_ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      source_comment: other_source_comment
    )

    assert_raises(Admin::CommentReports::RevokeBanService::RevokeTargetNotFoundError) do
      Admin::CommentReports::RevokeBanService.new(
        comment: @comment,
        actor: @admin,
        current_store: @store
      ).call
    end

    assert store_ban.reload.active?
  end

  test "does not revoke ban when source comment belongs to another store" do
    other_booth = Booth.create!(store: @other_store, name: "Other Source Booth", status: :live)
    other_stream_session = StreamSession.create!(
      store: @other_store,
      booth: other_booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/revoke-ban-other-source"
    )
    other_source_comment = Comment.create!(
      stream_session: other_stream_session,
      booth: other_booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "other store source comment"
    )
    store_ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      source_comment: other_source_comment
    )

    assert_raises(Admin::CommentReports::RevokeBanService::RevokeTargetNotFoundError) do
      Admin::CommentReports::RevokeBanService.new(
        comment: @comment,
        actor: @admin,
        current_store: @store
      ).call
    end

    assert store_ban.reload.active?
  end

  test "rejects comment from another store" do
    other_booth = Booth.create!(store: @other_store, name: "Other Booth", status: :live)
    other_stream_session = StreamSession.create!(
      store: @other_store,
      booth: other_booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/revoke-ban-other-store"
    )
    other_comment = Comment.create!(
      stream_session: other_stream_session,
      booth: other_booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "other store comment"
    )

    assert_raises(Admin::CommentReports::RevokeBanService::StoreMismatchError) do
      Admin::CommentReports::RevokeBanService.new(
        comment: other_comment,
        actor: @admin,
        current_store: @store
      ).call
    end
  end

  test "rejects non customer reported user" do
    cast_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @cast,
      kind: Comment::KIND_CHAT,
      body: "cast comment"
    )

    assert_raises(Admin::CommentReports::RevokeBanService::UnsupportedReportedUserError) do
      Admin::CommentReports::RevokeBanService.new(
        comment: cast_comment,
        actor: @admin,
        current_store: @store
      ).call
    end
  end

  private

  def create_report(comment:, status: :pending)
    reporter = User.create!(
      email: "revoke_ban_reporter_#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: :customer
    )

    CommentReport.create!(
      comment: comment,
      reporter_user: reporter,
      reported_user: comment.user,
      store: comment.stream_session.store,
      booth: comment.booth,
      stream_session: comment.stream_session,
      status: status
    )
  end
end
