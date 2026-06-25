# frozen_string_literal: true

require "test_helper"

class SystemAdminNotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @customer = User.create!(email: "customer_notifications@example.com", password: "password", role: :customer)
    @store_admin = User.create!(email: "admin_notifications@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_notifications@example.com", password: "password", role: :system_admin)
  end

  test "non system_admin cannot access" do
    sign_in @customer, scope: :user
    get system_admin_notifications_path
    assert_response :forbidden

    sign_in @store_admin, scope: :user
    get system_admin_notifications_path
    assert_response :forbidden
  end

  test "system_admin can list create update toggle and assign tags" do
    with_unpermitted_parameters_raising do
      tag = NotificationTag.create!(name: "maintenance")

      sign_in @system_admin, scope: :user

      get system_admin_notifications_path
      assert_response :success

      assert_difference [ "Notification.count", "NotificationTag.count" ], +1 do
        post system_admin_notifications_path, params: {
          notification: {
            title: "Scheduled maintenance",
            body: "We will perform maintenance tonight.",
            published_at: Time.current,
            enabled: true,
            notification_tag_ids: [ tag.id ],
            new_tag_names: "important"
          }
        }
      end

      assert_response :redirect
      assert_redirected_to system_admin_notifications_path

      notification = Notification.find_by!(title: "Scheduled maintenance")
      assert_equal @system_admin, notification.created_by_user
      assert_equal [ "important", "maintenance" ], notification.notification_tags.order(:name).pluck(:name)

      important = NotificationTag.find_by!(name: "important")
      patch system_admin_notification_path(notification), params: {
        notification: {
          title: "Updated maintenance",
          body: "Maintenance window changed.",
          published_at: 1.hour.ago,
          enabled: true,
          notification_tag_ids: [ important.id ]
        }
      }

      assert_response :redirect
      assert_redirected_to system_admin_notifications_path
      assert_equal "Updated maintenance", notification.reload.title
      assert_equal [ "important" ], notification.notification_tags.pluck(:name)

      patch system_admin_notification_path(notification), params: {
        notification: { enabled: false }
      }

      assert_response :redirect
      assert_redirected_to system_admin_notifications_path
      assert_not notification.reload.enabled?
      assert_empty Notification.published.where(id: notification.id)
      assert_equal [ "important" ], notification.notification_tags.pluck(:name)
    end
  end

  test "system_admin notification management does not list private notifications" do
    public_notice = Notification.create!(
      title: "Public managed notice",
      body: "body",
      published_at: Time.current,
      created_by_user: @system_admin
    )
    private_notice = Notification.create!(
      title: "Private support notice",
      body: "body",
      published_at: Time.current,
      created_by_user: @system_admin,
      recipient_user: @customer,
      link_path: "/support/inquiries/1"
    )

    sign_in @system_admin, scope: :user

    get system_admin_notifications_path
    assert_response :success
    assert_includes response.body, public_notice.title
    assert_not_includes response.body, private_notice.title
  end

  private

  def with_unpermitted_parameters_raising
    previous = ActionController::Parameters.action_on_unpermitted_parameters
    ActionController::Parameters.action_on_unpermitted_parameters = :raise
    yield
  ensure
    ActionController::Parameters.action_on_unpermitted_parameters = previous
  end
end
