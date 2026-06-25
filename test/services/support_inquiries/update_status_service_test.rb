# frozen_string_literal: true

require "test_helper"

class SupportInquiries::UpdateStatusServiceTest < ActiveSupport::TestCase
  setup do
    @customer = User.create!(email: "support_status_customer@example.com", password: "password", role: :customer)
    @store_admin = User.create!(email: "support_status_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "support_status_admin@example.com", password: "password", role: :system_admin)
    @support_inquiry = create_inquiry_for(@customer)
  end

  test "system admin can resolve inquiry and set resolved_at" do
    SupportInquiries::UpdateStatusService.new(
      actor: @system_admin,
      support_inquiry: @support_inquiry,
      status: "resolved"
    ).call

    @support_inquiry.reload

    assert_predicate @support_inquiry, :resolved?
    assert_not_nil @support_inquiry.resolved_at
  end

  test "system admin can return resolved inquiry to in progress and clear resolved_at" do
    @support_inquiry.update!(status: :resolved, resolved_at: 1.hour.ago)

    SupportInquiries::UpdateStatusService.new(
      actor: @system_admin,
      support_inquiry: @support_inquiry,
      status: "in_progress"
    ).call

    @support_inquiry.reload

    assert_predicate @support_inquiry, :in_progress?
    assert_nil @support_inquiry.resolved_at
  end

  test "system admin can return resolved inquiry to not started and clear resolved_at" do
    @support_inquiry.update!(status: :resolved, resolved_at: 1.hour.ago)

    SupportInquiries::UpdateStatusService.new(
      actor: @system_admin,
      support_inquiry: @support_inquiry,
      status: "not_started"
    ).call

    @support_inquiry.reload

    assert_predicate @support_inquiry, :not_started?
    assert_nil @support_inquiry.resolved_at
  end

  test "non system admin cannot update status" do
    assert_raises(SupportInquiries::UpdateStatusService::NotAllowedError) do
      SupportInquiries::UpdateStatusService.new(
        actor: @store_admin,
        support_inquiry: @support_inquiry,
        status: "resolved"
      ).call
    end
  end

  test "invalid status is rejected" do
    assert_raises(SupportInquiries::UpdateStatusService::InvalidStatusError) do
      SupportInquiries::UpdateStatusService.new(
        actor: @system_admin,
        support_inquiry: @support_inquiry,
        status: "closed"
      ).call
    end
  end

  private

  def create_inquiry_for(user)
    SupportInquiries::CreateService.new(
      user: user,
      attributes: {
        category: "question",
        subject: "Need help",
        reply_email: user.email
      },
      message_body: "Initial message"
    ).call.support_inquiry
  end
end
