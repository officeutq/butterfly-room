# frozen_string_literal: true

module Admin
  class DrinkItemsController < BaseController
    before_action :require_current_store!
    before_action :set_drink_item, only: %i[update destroy]

    def index
      @drink_item = current_store.drink_items.new(enabled: true, position: default_position)
      @drink_items = current_store.drink_items.ordered
    end

    def create
      @drink_item = current_store.drink_items.new(drink_item_params)
      if @drink_item.save
        redirect_to admin_drink_items_path, notice: "作成しました"
      else
        @drink_items = current_store.drink_items.ordered
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @drink_item.update(drink_item_params)
        redirect_to admin_drink_items_path, notice: "更新しました"
      else
        @drink_items = current_store.drink_items.ordered
        @drink_item = current_store.drink_items.new(enabled: true, position: default_position)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @drink_item.update!(enabled: false) # 論理削除
      redirect_to admin_drink_items_path, notice: "無効にしました"
    end

    private

    def set_drink_item
      @drink_item = current_store.drink_items.find(params[:id])
    end

    def drink_item_params
      params.require(:drink_item).permit(:name, :price_points, :position, :enabled, :icon_key)
    end

    def default_position
      last = current_store.drink_items.maximum(:position)
      last.present? ? last + 1 : 0
    end
  end
end
