# frozen_string_literal: true

module SystemAdmin
  class NotificationsController < SystemAdmin::BaseController
    before_action :set_notification, only: %i[edit update]
    before_action :set_tags, only: %i[new edit create update]

    def index
      @notifications =
        Notification
          .includes(:created_by_user, :notification_tags)
          .order(published_at: :desc, id: :desc)
    end

    def new
      @notification = Notification.new(enabled: true, published_at: Time.current)
      @selected_notification_tag_ids = []
      @new_tag_names = ""
    end

    def create
      @notification = Notification.new(notification_params)
      @notification.created_by_user = current_user
      @selected_notification_tag_ids = selected_tag_ids(@notification)
      @new_tag_names = new_tag_names_param

      if save_notification(@notification)
        redirect_to system_admin_notifications_path, notice: "お知らせを作成しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @selected_notification_tag_ids = @notification.notification_tag_ids
      @new_tag_names = ""
    end

    def update
      @notification.assign_attributes(notification_params)
      @selected_notification_tag_ids = selected_tag_ids(@notification)
      @new_tag_names = new_tag_names_param

      if save_notification(@notification)
        redirect_to system_admin_notifications_path, notice: "更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_notification
      @notification = Notification.find(params[:id])
    end

    def set_tags
      @tags = NotificationTag.order(:name, :id)
    end

    def notification_params
      params.require(:notification).permit(:title, :body, :enabled, :published_at)
    end

    def selected_tag_ids(notification)
      raw_ids = params.dig(:notification, :notification_tag_ids)
      return notification.notification_tag_ids if raw_ids.nil?

      raw_ids.reject(&:blank?).map(&:to_i)
    end

    def new_tag_names_param
      params.dig(:notification, :new_tag_names).to_s
    end

    def new_tag_names
      new_tag_names_param
        .split(/[,\n]/)
        .map(&:strip)
        .reject(&:blank?)
        .uniq
    end

    def save_notification(notification)
      ActiveRecord::Base.transaction do
        notification.save!
        notification.notification_tag_ids = (@selected_notification_tag_ids + created_tag_ids).uniq
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def created_tag_ids
      new_tag_names.map { |name| NotificationTag.find_or_create_by!(name: name).id }
    end
  end
end
