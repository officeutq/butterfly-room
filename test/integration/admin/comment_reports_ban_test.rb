# frozen_string_literal: true

require "test_helper"

class AdminCommentReportsBanTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Test Store")
    @other_store = Store.create!(name: "Other Store")

    @store_admin = User.create!(email: "admin_comment_report_ban@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "system_admin_comment_report_ban@example.com", password: "password", role: :system_admin)
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
    assert_equal @comment, ban.source_comment

    assert_equal "resolved", @comment.comment_reports.first.reload.status
  end

  test "store_admin can revoke comment-origin ban from comment_reports index" do
    @comment.comment_reports.update_all(status: CommentReport.statuses.fetch(:resolved))
    ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @store_admin,
      source_comment: @comment
    )

    sign_in @store_admin, scope: :user

    get admin_comment_reports_path(with_resolved: 1)
    assert_response :success
    assert_includes response.body, "BAN解除"

    assert_no_difference "StoreBan.count" do
      delete revoke_ban_admin_comment_report_path(@comment, with_resolved: 1)
    end

    assert_response :redirect
    assert_redirected_to admin_comment_reports_path(with_resolved: "1")
    assert_equal "BAN解除しました", flash[:notice]
    assert ban.reload.revoked?
    assert_equal @store_admin, ban.revoked_by_user
    assert_equal "comment_report_revoke", ban.revocation_reason
    assert_equal "resolved", @comment.comment_reports.first.reload.status

    follow_redirect!
    assert_response :success
    assert_select "form[action=?]", ban_admin_comment_report_path(@comment, with_resolved: 1)
    assert_select "form[action=?]", revoke_ban_admin_comment_report_path(@comment, with_resolved: 1), count: 0
  end

  test "comment-origin ban can be revoked from another report card for same reported user" do
    other_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "another reported comment"
    )
    other_reporter = User.create!(email: "other_reporter_comment_report_ban@example.com", password: "password", role: :customer)
    CommentReport.create!(
      comment: other_comment,
      reporter_user: other_reporter,
      reported_user: @customer,
      store: @store,
      booth: @booth,
      stream_session: @stream_session,
      status: :pending
    )

    sign_in @store_admin, scope: :user
    post ban_admin_comment_report_path(@comment)

    ban = StoreBan.active.find_by!(store: @store, customer_user: @customer)
    assert_equal @comment, ban.source_comment

    get admin_comment_reports_path(with_resolved: 1)
    assert_response :success
    assert_select "form[action=?]", revoke_ban_admin_comment_report_path(@comment, with_resolved: 1)
    assert_select "form[action=?]", revoke_ban_admin_comment_report_path(other_comment, with_resolved: 1)

    assert_no_difference "StoreBan.count" do
      delete revoke_ban_admin_comment_report_path(other_comment, with_resolved: 1)
    end

    assert_response :redirect
    assert ban.reload.revoked?
    assert_nil StoreBan.active.find_by(id: ban.id)
    assert_equal @store_admin, ban.revoked_by_user
    assert_equal "resolved", @comment.comment_reports.first.reload.status
  end

  test "store_admin cannot revoke manual system admin ban from comment report card" do
    @comment.comment_reports.update_all(status: CommentReport.statuses.fetch(:resolved))
    ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @system_admin
    )

    sign_in @store_admin, scope: :user

    get admin_comment_reports_path(with_resolved: 1)
    assert_response :success
    assert_includes response.body, "運営BAN中"
    assert_not_includes response.body, "BAN解除"

    delete revoke_ban_admin_comment_report_path(@comment, with_resolved: 1)

    assert_response :redirect
    assert_redirected_to admin_comment_reports_path(with_resolved: "1")
    assert_equal "解除できないBANです", flash[:alert]
    assert ban.reload.active?
  end

  test "store_admin can revoke comment-origin ban from another source comment for same customer" do
    @comment.comment_reports.update_all(status: CommentReport.statuses.fetch(:resolved))
    other_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "another reported comment"
    )
    ban = StoreBan.create!(
      store: @store,
      customer_user: @customer,
      created_by_store_admin_user: @store_admin,
      source_comment: other_comment
    )

    sign_in @store_admin, scope: :user

    get admin_comment_reports_path(with_resolved: 1)
    assert_response :success
    assert_select "form[action=?]", revoke_ban_admin_comment_report_path(@comment, with_resolved: 1)

    assert_no_difference "StoreBan.count" do
      delete revoke_ban_admin_comment_report_path(@comment, with_resolved: 1)
    end

    assert_response :redirect
    assert ban.reload.revoked?
    assert_nil StoreBan.active.find_by(id: ban.id)
  end

  test "store_admin cannot revoke other store ban" do
    other_booth = Booth.create!(store: @other_store, name: "Other Booth", status: :live)
    other_session = StreamSession.create!(
      store: @other_store,
      booth: other_booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/comment-report-other-store"
    )
    other_comment = Comment.create!(
      stream_session: other_session,
      booth: other_booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: "other store reported comment"
    )
    ban = StoreBan.create!(
      store: @other_store,
      customer_user: @customer,
      created_by_store_admin_user: @system_admin,
      source_comment: other_comment
    )

    sign_in @store_admin, scope: :user
    delete revoke_ban_admin_comment_report_path(other_comment)

    assert_response :not_found
    assert ban.reload.active?
  end
end
