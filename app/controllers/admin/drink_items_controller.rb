# frozen_string_literal: true

module Admin
  class DrinkItemsController < BaseController
    include RemovableImageAttachment
    include AttachmentPersistenceChecker

    before_action :require_current_store!
    before_action :set_drink_item, only: %i[update destroy]

    def index
      @drink_item = build_drink_item
      load_drink_items
      @editing_drink_item_id = params[:editing_id].to_i if params[:editing_id].present?
    end

    def create
      @drink_item = current_store.drink_items.new(drink_item_params)

      if @drink_item.save && ensure_attachment_persisted!(record: @drink_item, attachment_name: :custom_icon)
        purge_attachment_if_requested(
          record: @drink_item,
          attachment_name: :custom_icon,
          remove_param_name: :remove_custom_icon
        )

        onboarding_completed = current_store.onboarding_step_setup_drinks?
        current_store.complete_onboarding!

        notice =
          if onboarding_completed
            "ドリンクを作成しました。初回セットアップのチュートリアルが完了しました。お疲れさまでした！"
          else
            "作成しました"
          end

        redirect_to admin_drink_items_path, notice: notice
      else
        load_drink_items
        @editing_drink_item_id = nil
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @drink_item.update(drink_item_params) &&
          ensure_attachment_persisted!(record: @drink_item, attachment_name: :custom_icon)
        purge_attachment_if_requested(
          record: @drink_item,
          attachment_name: :custom_icon,
          remove_param_name: :remove_custom_icon
        )

        onboarding_completed = current_store.onboarding_step_setup_drinks?
        current_store.complete_onboarding!

        notice =
          if onboarding_completed
            "ドリンクを更新しました。初回セットアップのチュートリアルが完了しました。"
          else
            "更新しました"
          end

        redirect_to admin_drink_items_path, notice: notice
      else
        load_drink_items(replace_item: @drink_item)
        @editing_drink_item_id = @drink_item.id
        @drink_item = build_drink_item
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @drink_item.update!(enabled: false) # 論理削除
      redirect_to admin_drink_items_path, notice: "無効にしました"
    end

    private

    def set_drink_item
      @drink_item = current_store.drink_items.with_attached_custom_icon.find(params[:id])
    end

    def drink_item_params
      params.require(:drink_item)
            .permit(:name, :price_points, :position, :enabled, :icon_key, :custom_icon, :remove_custom_icon)
            .tap { |permitted| permitted.delete(:remove_custom_icon) }
    end

    def load_drink_items(replace_item: nil)
      @drink_items = current_store.drink_items.with_attached_custom_icon.ordered.to_a
      return if replace_item.blank? || replace_item.id.blank?

      @drink_items.map! { |item| item.id == replace_item.id ? replace_item : item }
    end

    def build_drink_item
      current_store.drink_items.new(enabled: true, position: default_position)
    end

    def default_position
      last = current_store.drink_items.maximum(:position)
      last.present? ? last + 1 : 0
    end
  end
end
