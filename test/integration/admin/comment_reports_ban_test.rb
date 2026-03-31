# frozen_string_literal: true

require "test_helper"

class AdminCommentReportsBanTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Test Store")

    @store_admin = User.create!(email: "admin_comment_report_ban@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)

    @cast = User.create!(email: "cast_comment_report_ban@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "customer_comment_report_ban@example.com", password: "password", role: :customer)

    @booth = Booth.create!(store: @store, name: "Booth 1", status: :offline)
    BoothCast.create!(booth: @booth, cast_user: @cast)

    @stream_session = StreamSession.create!(
      store: @store,
      booth: @booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/comment-report-ban"
    )
    @booth.update!(status: :live, current_stream_session: @stream_session)

    @comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "reported comment"
    )

    reporter = User.create!(email: "reporter_comment_report_ban@example.com", password: "password", role: :customer)
    CommentReport.create!(
      comment: @comment,
      reporter_user: reporter,
      reported_user: @customer,
      store: @store,
      booth: @booth,
      stream_session: @stream_session,
      status: :pending
    )
  end

  test "store_admin can ban reported user from comment_reports index" do
    sign_in @store_admin, scope: :user

    post ban_admin_comment_report_path(@comment)

    assert_response :redirect
    assert_redirected_to admin_comment_reports_path
    assert_equal "BANしました", flash[:notice]

    ban = StoreBan.find_by(store: @store, customer_user: @customer)
    assert ban.present?
    assert_equal @store_admin.id, ban.created_by_store_admin_user_id
    assert_equal "コメント通報による対応", ban.reason

    assert_equal "resolved", @comment.comment_reports.first.reload.status
  end
end
