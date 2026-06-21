# frozen_string_literal: true

require "test_helper"

class NotificationReadTest < ActiveSupport::TestCase
  setup do
    @system_admin = User.create!(email: "notification_read_admin@example.com", password: "password", role: :system_admin)
    @user = User.create!(email: "notification_read_user@example.com", password: "password", role: :customer)
    @notification = Notification.create!(
      title: "notice",
      body: "body",
      published_at: Time.current,
      created_by_user: @system_admin
    )
  end

  test "notification_id + user_id is unique at DB level" do
    NotificationRead.create!(notification: @notification, user: @user, read_at: Time.current)

    assert_raises(ActiveRecord::RecordNotUnique) do
      NotificationRead.create!(notification: @notification, user: @user, read_at: Time.current)
    end
  end
end
