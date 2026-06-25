# frozen_string_literal: true

class NotificationsController < ApplicationController
  def index
    @tags = NotificationTag.order(:name, :id)
    @selected_tag_ids = selected_tag_ids

    notifications = Notification.visible_to(current_user).includes(:notification_tags)
    if @selected_tag_ids.any?
      notifications =
        notifications
          .joins(:notification_taggings)
          .where(notification_taggings: { notification_tag_id: @selected_tag_ids })
          .distinct
    end

    @notifications = notifications.to_a
    @read_notification_ids =
      current_user
        .notification_reads
        .where(notification_id: @notifications.map(&:id))
        .pluck(:notification_id)
  end

  def show
    @notification = Notification.visible_to(current_user).includes(:notification_tags).find(params[:id])

    mark_notification_read
    redirect_to @notification.link_path if @notification.link_path.present?
  end

  private

  def selected_tag_ids
    Array(params[:tag_ids]).reject(&:blank?).map(&:to_i)
  end

  def mark_notification_read
    notification_read = current_user.notification_reads.find_or_initialize_by(notification: @notification)
    notification_read.read_at = Time.current
    notification_read.save!
  rescue ActiveRecord::RecordNotUnique
    current_user.notification_reads.where(notification: @notification).update_all(
      read_at: Time.current,
      updated_at: Time.current
    )
  end
end
