# frozen_string_literal: true

require "test_helper"

class Admin::CommentReports::BanServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Test Store")
    @other_store = Store.create!(name: "Other Store")

    @admin = User.create!(email: "admin_ban_service@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)

    @cast = User.create!(email: "cast_ban_service@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "customer_ban_service@example.com", password: "password", role: :customer)
    @other_customer = User.create!(email: "other_customer_ban_service@example.com", password: "password", role: :customer)

    @booth = Booth.create!(store: @store, name: "Booth 1", status: :offline)
    BoothCast.create!(booth: @booth, cast_user: @cast)

    @stream_session = StreamSession.create!(
      store: @store,
      booth: @booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/ban-service"
    )
    @booth.update!(status: :live, current_stream_session: @stream_session)

    @target_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "target comment"
    )

    @other_comment_same_user = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "other comment same user"
    )

    @other_comment_other_user = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @other_customer,
      kind: Comment::KIND_CHAT,
      body: "other comment other user"
    )

    @target_pending_report = create_report(comment: @target_comment, reporter_suffix: "target_pending")
    @target_rejected_report = create_report(comment: @target_comment, reporter_suffix: "target_rejected", status: :rejected)
    @other_pending_same_user_report = create_report(comment: @other_comment_same_user, reporter_suffix: "other_same_user_pending")
    @other_pending_other_user_report = create_report(comment: @other_comment_other_user, reporter_suffix: "other_user_pending")
  end

  test "customer を BAN すると store_ban を作成し対象 comment の pending 通報だけ resolved にする" do
    assert_difference "StoreBan.count", 1 do
      Admin::CommentReports::BanService.new(
        comment: @target_comment,
        actor: @admin,
        current_store: @store
      ).call
    end

    ban = StoreBan.find_by!(store: @store, customer_user: @customer)

    assert_equal @admin, ban.created_by_store_admin_user
    assert_equal "コメント通報による対応", ban.reason

    assert_equal "resolved", @target_pending_report.reload.status
    assert_equal "rejected", @target_rejected_report.reload.status
    assert_equal "pending", @other_pending_same_user_report.reload.status
    assert_equal "pending", @other_pending_other_user_report.reload.status
  end

  test "すでに BAN 済みでも二重作成しない" do
    StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @admin,
      reason: "既存BAN"
    )

    assert_no_difference "StoreBan.count" do
      Admin::CommentReports::BanService.new(
        comment: @target_comment,
        actor: @admin,
        current_store: @store
      ).call
    end

    assert_equal "resolved", @target_pending_report.reload.status
  end

  test "reported_user が customer 以外だと例外" do
    cast_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @cast,
      kind: Comment::KIND_CHAT,
      body: "cast comment"
    )
    cast_report = create_report(comment: cast_comment, reporter_suffix: "cast_report", reported_user: @cast)

    assert_raises(Admin::CommentReports::BanService::UnsupportedReportedUserError) do
      Admin::CommentReports::BanService.new(
        comment: cast_comment,
        actor: @admin,
        current_store: @store
      ).call
    end

    assert_equal "pending", cast_report.reload.status
    assert_nil StoreBan.find_by(store: @store, customer_user: @cast)
  end

  test "comment と current_store が不一致だと例外" do
    other_booth = Booth.create!(store: @other_store, name: "Other Booth", status: :offline)
    other_stream_session = StreamSession.create!(
      store: @other_store,
      booth: other_booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/other-store"
    )
    other_comment = Comment.create!(
      stream_session: other_stream_session,
      booth: other_booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "other store comment"
    )

    assert_raises(Admin::CommentReports::BanService::StoreMismatchError) do
      Admin::CommentReports::BanService.new(
        comment: other_comment,
        actor: @admin,
        current_store: @store
      ).call
    end
  end

  private

  def create_report(comment:, reporter_suffix:, status: :pending, reported_user: comment.user)
    reporter = User.create!(
      email: "#{reporter_suffix}@example.com",
      password: "password",
      role: :customer
    )

    CommentReport.create!(
      comment: comment,
      reporter_user: reporter,
      reported_user: reported_user,
      store: comment.stream_session.store,
      booth: comment.booth,
      stream_session: comment.stream_session,
      status: status
    )
  end
end
