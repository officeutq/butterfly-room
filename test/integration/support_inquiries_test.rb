# frozen_string_literal: true

require "test_helper"

class SupportInquiriesTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Support Flow Store")
    @booth = Booth.create!(store: @store, name: "Support Flow Booth", status: :offline)
    @customer = User.create!(email: "support_flow_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "support_flow_cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "support_flow_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "support_flow_system_admin@example.com", password: "password", role: :system_admin)
    @other_customer = User.create!(email: "support_flow_other@example.com", password: "password", role: :customer)

    BoothCast.create!(booth: @booth, cast_user: @cast)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
  end

  test "guest is redirected to login" do
    get support_inquiries_path

    assert_redirected_to new_user_session_path
  end

  test "new form defaults reply email to current user email" do
    sign_in @customer, scope: :user

    get new_support_inquiry_path

    assert_response :success
    assert_select "input[name='support_inquiry[reply_email]'][value=?]", @customer.email
  end

  test "customer cast and store admin can create support inquiries" do
    [
      [ @customer, nil ],
      [ @cast, @store ],
      [ @store_admin, @store ]
    ].each do |user, expected_store|
      sign_in user, scope: :user

      assert_difference -> { SupportInquiry.count }, +1 do
        assert_difference -> { SupportInquiryMessage.count }, +1 do
          post support_inquiries_path, params: create_params(subject: "Help #{user.role}")
        end
      end

      inquiry = SupportInquiry.order(:id).last
      message = inquiry.support_inquiry_messages.first

      assert_redirected_to support_inquiry_path(inquiry)
      assert_equal user, inquiry.user
      if expected_store.present?
        assert_equal expected_store, inquiry.store
      else
        assert_nil inquiry.store
      end
      assert_equal "question", inquiry.category
      assert_equal "not_started", inquiry.status
      assert_equal "user", inquiry.last_message_sender_kind
      assert_in_delta inquiry.last_message_at.to_f, message.created_at.to_f, 1
      assert_equal "Initial support message", message.body

      sign_out :user
    end
  end

  test "system admin cannot access user support inquiries" do
    inquiry = create_inquiry_for(@customer, subject: "Customer inquiry")

    sign_in @system_admin, scope: :user

    get support_inquiries_path
    assert_response :forbidden

    get new_support_inquiry_path
    assert_response :forbidden

    post support_inquiries_path, params: create_params
    assert_response :forbidden

    get support_inquiry_path(inquiry)
    assert_response :forbidden
  end

  test "index lists only current user inquiries" do
    own_inquiry = create_inquiry_for(@customer, subject: "Own inquiry")
    other_inquiry = create_inquiry_for(@other_customer, subject: "Other inquiry")

    sign_in @customer, scope: :user

    get support_inquiries_path

    assert_response :success
    assert_includes response.body, own_inquiry.subject
    assert_not_includes response.body, other_inquiry.subject
  end

  test "show displays own inquiry messages and hides other users inquiries" do
    own_inquiry = create_inquiry_for(@customer, subject: "Own detail", body: "Own message")
    other_inquiry = create_inquiry_for(@other_customer, subject: "Other detail", body: "Other message")

    sign_in @customer, scope: :user

    get support_inquiry_path(own_inquiry)
    assert_response :success
    assert_includes response.body, own_inquiry.subject
    assert_includes response.body, "Own message"

    get support_inquiry_path(other_inquiry)
    assert_response :not_found
  end

  test "dashboard links to support inquiries for user roles only" do
    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      get dashboard_path

      assert_response :success
      assert_select "a[href=?]", support_inquiries_path, minimum: 1

      sign_out :user
    end

    sign_in @system_admin, scope: :user

    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", support_inquiries_path, count: 0
  end

  private

  def create_params(subject: "Need help", body: "Initial support message")
    {
      support_inquiry: {
        category: "question",
        subject: subject,
        reply_email: "reply@example.com",
        body: body
      }
    }
  end

  def create_inquiry_for(user, subject:, body: "Initial support message")
    SupportInquiries::CreateService.new(
      user: user,
      attributes: {
        category: "question",
        subject: subject,
        reply_email: user.email
      },
      message_body: body
    ).call.support_inquiry
  end
end
