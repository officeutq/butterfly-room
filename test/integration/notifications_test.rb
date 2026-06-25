# frozen_string_literal: true

require "test_helper"

class NotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @system_admin = User.create!(email: "sys_user_notifications@example.com", password: "password", role: :system_admin)
    @customer = User.create!(email: "customer_user_notifications@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "cast_user_notifications@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "store_admin_user_notifications@example.com", password: "password", role: :store_admin)
  end

  test "guest is redirected to login" do
    get notifications_path

    assert_response :redirect
    assert_redirected_to new_user_session_path
  end

  test "all roles can access index and show" do
    notification = create_notification(title: "Role notice")

    [ @customer, @cast, @store_admin, @system_admin ].each do |user|
      sign_in user, scope: :user

      get notifications_path
      assert_response :success

      get notification_path(notification)
      assert_response :success

      sign_out :user
    end
  end

  test "index filters by tags and shows unread marker" do
    maintenance = NotificationTag.create!(name: "user-maintenance")
    event = NotificationTag.create!(name: "user-event")

    maintenance_notice = create_notification(title: "Maintenance notice", tags: [ maintenance ])
    event_notice = create_notification(title: "Event notice", tags: [ event ])
    create_notification(title: "Disabled notice", enabled: false, tags: [ maintenance ])
    create_notification(title: "Future notice", published_at: 1.day.from_now, tags: [ maintenance ])
    NotificationRead.create!(notification: event_notice, user: @customer, read_at: Time.current)

    sign_in @customer, scope: :user

    get notifications_path(tag_ids: [ maintenance.id ])
    assert_response :success
    assert_includes response.body, maintenance_notice.title
    assert_not_includes response.body, event_notice.title
    assert_not_includes response.body, "Disabled notice"
    assert_not_includes response.body, "Future notice"
    assert_select ".notification-unread-dot", count: 1

    get notifications_path
    assert_response :success
    assert_includes response.body, maintenance_notice.title
    assert_includes response.body, event_notice.title
    assert_not_includes response.body, "Disabled notice"
    assert_not_includes response.body, "Future notice"
    assert_select ".notification-unread-dot", count: 1
  end

  test "show marks notification as read and clears footer badge" do
    notification = create_notification(title: "Unread notice")

    sign_in @customer, scope: :user

    get notifications_path
    assert_response :success
    assert_select ".app-footer-nav-badge", count: 1

    assert_difference "NotificationRead.count", +1 do
      get notification_path(notification)
    end
    assert_response :success
    assert_select ".app-footer-nav-badge", count: 0

    assert_no_difference "NotificationRead.count" do
      get notification_path(notification)
    end
    assert_response :success

    get notifications_path
    assert_response :success
    assert_select ".app-footer-nav-badge", count: 0
    assert_select ".notification-unread-dot", count: 0
  end

  test "private notifications are visible only to the recipient" do
    public_notice = create_notification(title: "Public notice")
    recipient_notice = create_notification(title: "Recipient notice", recipient_user: @customer)
    other_notice = create_notification(title: "Other private notice", recipient_user: @cast)

    sign_in @customer, scope: :user

    get notifications_path
    assert_response :success
    assert_includes response.body, public_notice.title
    assert_includes response.body, recipient_notice.title
    assert_not_includes response.body, other_notice.title
    assert_select ".notification-unread-dot", count: 2

    get notification_path(other_notice)
    assert_response :not_found
  end

  test "show redirects link_path notification after marking it as read" do
    notification = create_notification(
      title: "Linked notice",
      recipient_user: @customer,
      link_path: dashboard_path
    )

    sign_in @customer, scope: :user

    assert_difference "NotificationRead.count", +1 do
      get notification_path(notification)
    end

    assert_redirected_to dashboard_path
    assert_not notification.reload.unread_for?(@customer)
  end

  test "disabled notification is not visible from public show" do
    notification = create_notification(title: "Disabled public notice", enabled: false)

    sign_in @system_admin, scope: :user

    get notification_path(notification)
    assert_response :not_found
  end

  private

  def create_notification(
    title:,
    body: "body",
    enabled: true,
    published_at: 1.hour.ago,
    recipient_user: nil,
    link_path: nil,
    tags: []
  )
    notification = Notification.create!(
      title: title,
      body: body,
      enabled: enabled,
      published_at: published_at,
      created_by_user: @system_admin,
      recipient_user: recipient_user,
      link_path: link_path
    )
    notification.notification_tags = tags
    notification
  end
end
