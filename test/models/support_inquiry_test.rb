# frozen_string_literal: true

require "test_helper"

class SupportInquiryTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "support_inquiry_user@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "support_inquiry_cast@example.com", password: "password", role: :cast)
    @store = Store.create!(name: "Support Store")
    @booth = Booth.create!(store: @store, name: "Support Booth", status: :offline)
    @stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast
    )
    @source_comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @user,
      kind: Comment::KIND_CHAT,
      body: "hello",
      metadata: {}
    )
  end

  test "valid with required attributes" do
    assert build_inquiry.valid?
  end

  test "required attributes must be present" do
    required_attributes = [
      :user,
      :category,
      :status,
      :subject,
      :reply_email,
      :name_snapshot,
      :role_snapshot,
      :last_message_at,
      :last_message_sender_kind
    ]

    required_attributes.each do |attribute|
      inquiry = build_inquiry(attribute => nil)

      assert_not inquiry.valid?, "#{attribute} should be required"
    end
  end

  test "category enum works" do
    inquiry = build_inquiry(category: :bug)
    assert inquiry.bug?

    inquiry.category = :request
    assert inquiry.request?

    inquiry.category = :question
    assert inquiry.question?

    inquiry.category = :report
    assert inquiry.report?

    inquiry.category = :other
    assert inquiry.other?
  end

  test "status enum works" do
    inquiry = build_inquiry(status: :not_started)
    assert inquiry.not_started?

    inquiry.status = :in_progress
    assert inquiry.in_progress?

    inquiry.status = :resolved
    assert inquiry.resolved?
  end

  test "last message sender kind enum works" do
    inquiry = build_inquiry(last_message_sender_kind: :user)
    assert inquiry.last_message_sender_user?

    inquiry.last_message_sender_kind = :system_admin
    assert inquiry.last_message_sender_system_admin?
  end

  test "subject has maximum length 120" do
    assert build_inquiry(subject: "a" * 120).valid?

    inquiry = build_inquiry(subject: "a" * 121)

    assert_not inquiry.valid?
    assert inquiry.errors.details[:subject].any? { |detail| detail[:error] == :too_long }
  end

  test "reply email must have valid format" do
    assert build_inquiry(reply_email: "reply@example.com").valid?

    inquiry = build_inquiry(reply_email: "invalid-email")

    assert_not inquiry.valid?
    assert inquiry.errors.details[:reply_email].any? { |detail| detail[:error] == :invalid }
  end

  test "store and source comment are optional" do
    inquiry = build_inquiry(store: nil, store_name_snapshot: nil, source_comment: nil)

    assert inquiry.valid?
  end

  test "associations connect user store source comment and messages" do
    inquiry = build_inquiry
    inquiry.save!
    message = SupportInquiryMessage.create!(
      support_inquiry: inquiry,
      sender_user: @user,
      sender_kind: :user,
      body: "message"
    )

    assert_equal [ inquiry ], @user.support_inquiries.to_a
    assert_equal [ inquiry ], @store.support_inquiries.to_a
    assert_equal [ inquiry ], @source_comment.support_inquiries.to_a
    assert_equal [ message ], inquiry.support_inquiry_messages.to_a
  end

  private

  def build_inquiry(attributes = {})
    SupportInquiry.new(
      {
        user: @user,
        store: @store,
        category: :question,
        status: :not_started,
        subject: "Need help",
        reply_email: "reply@example.com",
        name_snapshot: "Customer Name",
        role_snapshot: "customer",
        store_name_snapshot: @store.name,
        source_comment: @source_comment,
        last_message_at: Time.current,
        last_message_sender_kind: :user
      }.merge(attributes)
    )
  end
end
