# frozen_string_literal: true

require "test_helper"

class SupportInquiriesFromCommentReportTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Report Source Store")
    @other_store = Store.create!(name: "Other Report Source Store")

    @store_admin = User.create!(email: "report_source_admin@example.com", password: "password", role: :store_admin)
    @customer = User.create!(email: "report_source_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(
      email: "report_source_cast@example.com",
      password: "password",
      role: :cast,
      display_name: "Reported Cast"
    )
    @other_cast = User.create!(email: "report_source_other_cast@example.com", password: "password", role: :cast)

    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)

    @booth = Booth.create!(store: @store, name: "Report Source Booth", status: :offline)
    @stream_session = StreamSession.create!(
      store: @store,
      booth: @booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      title: "Report Source Stream"
    )
    @comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @cast,
      kind: Comment::KIND_CHAT,
      body: "Escalation target body",
      metadata: {}
    )
    @comment_report = create_report(comment: @comment, reported_user: @cast, store: @store, booth: @booth, stream_session: @stream_session)

    @other_booth = Booth.create!(store: @other_store, name: "Other Report Source Booth", status: :offline)
    @other_stream_session = StreamSession.create!(
      store: @other_store,
      booth: @other_booth,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @other_cast,
      title: "Other Report Source Stream"
    )
    @other_comment = Comment.create!(
      stream_session: @other_stream_session,
      booth: @other_booth,
      user: @other_cast,
      kind: Comment::KIND_CHAT,
      body: "Other escalation target body",
      metadata: {}
    )
    create_report(
      comment: @other_comment,
      reported_user: @other_cast,
      store: @other_store,
      booth: @other_booth,
      stream_session: @other_stream_session
    )
  end

  test "store admin can open support inquiry form from report card" do
    sign_in_store_admin_with_current_store

    get admin_comment_reports_path

    assert_response :success
    assert_select "a[href=?]", new_support_inquiry_path(source_comment_id: @comment.id), text: /運営に報告/
  end

  test "source comment initializes support inquiry form" do
    sign_in_store_admin_with_current_store

    get new_support_inquiry_path(source_comment_id: @comment.id)

    assert_response :success
    assert_select "input[name='support_inquiry[source_comment_id]'][value=?]", @comment.id.to_s
    assert_select "select[name='support_inquiry[category]'] option[value='report'][selected]"
    assert_select "input[name='support_inquiry[subject]'][value=?]", "通報に関する運営報告"
    assert_includes response.body, @store.name
    assert_includes response.body, "Report Source Stream"
    assert_includes response.body, "Reported Cast"
    assert_includes response.body, "配信者"
    assert_includes response.body, "ロール: 配信者"
    assert_includes response.body, "Escalation target body"
    assert_includes response.body, "comment ID: #{@comment.id}"
  end

  test "store admin can create source comment inquiry without changing report status" do
    sign_in_store_admin_with_current_store

    assert_difference -> { SupportInquiry.count }, +1 do
      assert_difference -> { SupportInquiryMessage.count }, +1 do
        post support_inquiries_path, params: source_create_params(@comment)
      end
    end

    inquiry = SupportInquiry.order(:id).last

    assert_redirected_to support_inquiry_path(inquiry)
    assert_equal @store_admin, inquiry.user
    assert_equal @store, inquiry.store
    assert_equal @comment, inquiry.source_comment
    assert_equal "report", inquiry.category
    assert_equal "通報に関する運営報告", inquiry.subject
    assert_equal "pending", @comment_report.reload.status
  end

  test "store admin cannot create source comment inquiry for other store comment" do
    sign_in_store_admin_with_current_store

    get new_support_inquiry_path(source_comment_id: @other_comment.id)
    assert_response :not_found

    assert_no_difference -> { SupportInquiry.count } do
      assert_no_difference -> { SupportInquiryMessage.count } do
        post support_inquiries_path, params: source_create_params(@other_comment)
      end
    end

    assert_response :not_found
  end

  test "customer and cast cannot use source comment inquiry flow" do
    [ @customer, @cast ].each do |user|
      sign_in user, scope: :user

      get new_support_inquiry_path(source_comment_id: @comment.id)
      assert_response :forbidden

      assert_no_difference -> { SupportInquiry.count } do
        post support_inquiries_path, params: source_create_params(@comment)
      end
      assert_response :forbidden

      sign_out :user
    end
  end

  private

  def sign_in_store_admin_with_current_store
    sign_in @store_admin, scope: :user
    post admin_current_store_path, params: { store_id: @store.id }
    assert_redirected_to dashboard_path
  end

  def source_create_params(comment)
    {
      support_inquiry: {
        category: "report",
        subject: "通報に関する運営報告",
        reply_email: "report-source-reply@example.com",
        body: "Please review this comment",
        source_comment_id: comment.id
      }
    }
  end

  def create_report(comment:, reported_user:, store:, booth:, stream_session:)
    reporter = User.create!(
      email: "reporter-#{comment.id}@example.com",
      password: "password",
      role: :customer
    )

    CommentReport.create!(
      comment: comment,
      reporter_user: reporter,
      reported_user: reported_user,
      store: store,
      booth: booth,
      stream_session: stream_session,
      status: :pending
    )
  end
end
