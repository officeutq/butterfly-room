# frozen_string_literal: true

require "test_helper"

class SystemAdminSupportInquiriesTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "System Support Store")
    @booth = Booth.create!(store: @store, name: "System Support Booth", status: :offline)
    @customer = User.create!(email: "system_support_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "system_support_cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "system_support_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "system_support_admin@example.com", password: "password", role: :system_admin)

    BoothCast.create!(booth: @booth, cast_user: @cast)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
  end

  test "guest is redirected to login" do
    get system_admin_support_inquiries_path

    assert_redirected_to new_user_session_path
  end

  test "non system admins cannot access management screens" do
    support_inquiry = create_inquiry_for(@customer, subject: "Forbidden target")

    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      get system_admin_support_inquiries_path
      assert_response :forbidden

      get system_admin_support_inquiry_path(support_inquiry)
      assert_response :forbidden

      patch system_admin_support_inquiry_path(support_inquiry), params: {
        support_inquiry: { status: "resolved" }
      }
      assert_response :forbidden

      sign_out :user
    end
  end

  test "system admin dashboard links to support inquiry management" do
    sign_in @system_admin, scope: :user

    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", system_admin_support_inquiries_path, minimum: 1

    sign_out :user
    sign_in @customer, scope: :user

    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", system_admin_support_inquiries_path, count: 0
  end

  test "system admin can list inquiries ordered by last message descending" do
    older = create_inquiry_for(@customer, subject: "Older support inquiry")
    newer = create_inquiry_for(@cast, subject: "Newer support inquiry", store: @store)
    older.update!(last_message_at: 2.days.ago)
    newer.update!(last_message_at: 1.hour.ago)

    sign_in @system_admin, scope: :user

    get system_admin_support_inquiries_path

    assert_response :success
    assert_includes response.body, older.subject
    assert_includes response.body, newer.subject
    assert_operator response.body.index(newer.subject), :<, response.body.index(older.subject)
  end

  test "system admin can filter inquiries by status category and role" do
    matching = create_inquiry_for(@customer, subject: "Matching inquiry", category: "bug")
    matching.update!(status: :resolved, resolved_at: 1.hour.ago)
    filtered_out = create_inquiry_for(@cast, subject: "Filtered out inquiry", category: "question")

    sign_in @system_admin, scope: :user

    get system_admin_support_inquiries_path, params: {
      status: "resolved",
      category: "bug",
      role_snapshot: "customer"
    }

    assert_response :success
    assert_includes response.body, matching.subject
    assert_not_includes response.body, filtered_out.subject
    assert_select "select[name='role_snapshot'] option[value='customer']", text: "視聴者"
    assert_select ".referral-code-value", text: "視聴者"
  end

  test "system admin can view inquiry details with messages and source comment" do
    source_comment = create_source_comment(body: "Reported comment body")
    support_inquiry = create_inquiry_for(
      @store_admin,
      subject: "Source comment inquiry",
      body: "Initial inquiry body",
      store: @store,
      source_comment: source_comment
    )

    sign_in @system_admin, scope: :user

    get system_admin_support_inquiry_path(support_inquiry)

    assert_response :success
    assert_includes response.body, support_inquiry.subject
    assert_includes response.body, support_inquiry.reply_email
    assert_includes response.body, "Initial inquiry body"
    assert_includes response.body, "Reported comment body"
    assert_select ".referral-code-value", text: "店舗管理者"
  end

  test "system admin can update status and resolved_at" do
    support_inquiry = create_inquiry_for(@customer, subject: "Status target")

    sign_in @system_admin, scope: :user

    patch system_admin_support_inquiry_path(support_inquiry), params: {
      support_inquiry: { status: "resolved" }
    }

    assert_redirected_to system_admin_support_inquiry_path(support_inquiry)
    support_inquiry.reload
    assert_predicate support_inquiry, :resolved?
    assert_not_nil support_inquiry.resolved_at

    patch system_admin_support_inquiry_path(support_inquiry), params: {
      support_inquiry: { status: "in_progress" }
    }

    assert_redirected_to system_admin_support_inquiry_path(support_inquiry)
    support_inquiry.reload
    assert_predicate support_inquiry, :in_progress?
    assert_nil support_inquiry.resolved_at

    patch system_admin_support_inquiry_path(support_inquiry), params: {
      support_inquiry: { status: "not_started" }
    }

    assert_redirected_to system_admin_support_inquiry_path(support_inquiry)
    support_inquiry.reload
    assert_predicate support_inquiry, :not_started?
    assert_nil support_inquiry.resolved_at
  end

  private

  def create_inquiry_for(user, subject:, category: "question", body: "Initial message", store: nil, source_comment: nil)
    SupportInquiries::CreateService.new(
      user: user,
      store: store,
      source_comment: source_comment,
      attributes: {
        category: category,
        subject: subject,
        reply_email: user.email
      },
      message_body: body
    ).call.support_inquiry
  end

  def create_source_comment(body:)
    stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast
    )

    Comment.create!(
      stream_session: stream_session,
      booth: @booth,
      user: @customer,
      kind: Comment::KIND_CHAT,
      body: body,
      metadata: {}
    )
  end
end
