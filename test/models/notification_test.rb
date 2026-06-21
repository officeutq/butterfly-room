# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @system_admin = User.create!(email: "notification_admin@example.com", password: "password", role: :system_admin)
  end

  test "published returns enabled notifications whose published_at is in the past ordered newest first" do
    older = Notification.create!(
      title: "older",
      body: "body",
      published_at: 2.days.ago,
      created_by_user: @system_admin
    )
    newer = Notification.create!(
      title: "newer",
      body: "body",
      published_at: 1.day.ago,
      created_by_user: @system_admin
    )
    Notification.create!(
      title: "disabled",
      body: "body",
      enabled: false,
      published_at: 1.hour.ago,
      created_by_user: @system_admin
    )
    Notification.create!(
      title: "future",
      body: "body",
      published_at: 1.day.from_now,
      created_by_user: @system_admin
    )

    assert_equal [ newer, older ], Notification.published.to_a
  end

  test "associations connect notifications tags reads and creator" do
    user = User.create!(email: "notification_reader@example.com", password: "password", role: :customer)
    notification = Notification.create!(
      title: "notice",
      body: "body",
      published_at: Time.current,
      created_by_user: @system_admin
    )
    tag = NotificationTag.create!(name: "maintenance")

    notification.notification_tags << tag
    NotificationRead.create!(notification: notification, user: user, read_at: Time.current)

    assert_equal @system_admin, notification.created_by_user
    assert_equal [ notification ], @system_admin.created_notifications.to_a
    assert_equal [ tag ], notification.notification_tags.to_a
    assert_equal [ notification ], tag.notifications.to_a
    assert_equal [ notification ], user.notification_reads.map(&:notification)
  end

  test "unread checks are scoped to the user" do
    reader = User.create!(email: "notification_unread_reader@example.com", password: "password", role: :customer)
    other_user = User.create!(email: "notification_unread_other@example.com", password: "password", role: :customer)
    notification = Notification.create!(
      title: "notice",
      body: "body",
      published_at: Time.current,
      created_by_user: @system_admin
    )

    NotificationRead.create!(notification: notification, user: other_user, read_at: Time.current)

    assert notification.unread_for?(reader)
    assert reader.unread_notifications_exists?

    NotificationRead.create!(notification: notification, user: reader, read_at: Time.current)

    assert_not notification.unread_for?(reader)
    assert_not reader.unread_notifications_exists?
  end
end
