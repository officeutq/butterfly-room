# frozen_string_literal: true

require "test_helper"

class NotificationTaggingTest < ActiveSupport::TestCase
  setup do
    @system_admin = User.create!(email: "notification_tagging_admin@example.com", password: "password", role: :system_admin)
    @notification = Notification.create!(
      title: "notice",
      body: "body",
      published_at: Time.current,
      created_by_user: @system_admin
    )
    @tag = NotificationTag.create!(name: "maintenance")
  end

  test "notification_id + notification_tag_id is unique at DB level" do
    NotificationTagging.create!(notification: @notification, notification_tag: @tag)

    assert_raises(ActiveRecord::RecordNotUnique) do
      NotificationTagging.create!(notification: @notification, notification_tag: @tag)
    end
  end
end
