# frozen_string_literal: true

module SystemAdmin
  class EffectsController < SystemAdmin::BaseController
    before_action :set_effect, only: %i[edit update]

    def index
      @effects = Effect.order(:position, :id)
    end

    def new
      @effect = Effect.new(enabled: true, position: default_position)
    end

    def create
      @effect = Effect.new(effect_params)

      if @effect.save
        redirect_to system_admin_effects_path, notice: "Effectを作成しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @effect.update(effect_params)
        redirect_to system_admin_effects_path, notice: "更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_effect
      @effect = Effect.find(params[:id])
    end

    def effect_params
      params.require(:effect).permit(
        :name,
        :key,
        :zip_filename,
        :icon_path,
        :enabled,
        :position
      )
    end

    def default_position
      last = Effect.maximum(:position)
      last.present? ? last + 1 : 0
    end
  end
end
