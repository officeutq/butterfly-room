# frozen_string_literal: true

module Admin
  class StoresController < Admin::BaseController
    before_action :set_store, only: %i[edit update]
    before_action :authorize_store_edit!, only: %i[edit update]
    before_action -> { require_selected_store!(@store) }, only: %i[edit update]
    before_action :require_store_registration_proxy!, only: %i[new create]
    helper_method :store_edit_return_path

    def index
      load_selectable_stores
    end

    def new
      @form = Stores::ProxyRegistrationForm.new(actor: current_user)
    end

    def create
      @form = Stores::ProxyRegistrationForm.new(proxy_store_params.merge(actor: current_user))

      if @form.save
        normalize_current_selection
        redirect_to edit_admin_store_path(@form.store), notice: "代行対象店舗を作成しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def select_modal
      load_selectable_stores
      return render_selection_problem(selection_error_message) unless current_selection.success?
      if current_store && (!current_selection.store_switchable? || params[:required].present?)
        redirect_to selection_return_path(kind: :store)
      elsif @stores.empty?
        render_selection_problem("管理可能な店舗がありません")
      elsif turbo_frame_request?
        render :select_modal, layout: false, status: :ok
      else
        redirect_to admin_stores_path(return_to: @return_to, return_to_key: @return_to_key)
      end
    end

    def edit
    end

    def update
      attributes = store_params.to_h.symbolize_keys
      upload = attributes.delete(:thumbnail)
      remove_thumbnail = attributes.delete(:remove_thumbnail)

      begin
        Stores::UpdateService.new(
          store: @store,
          attributes:,
          actor_user: current_user, source: "web", request_id: request.request_id,
          image_update: image_pair_payload,
          legacy_thumbnail_upload: upload,
          remove_legacy_thumbnail: remove_thumbnail
        ).call
      rescue Stores::UpdateService::StaleImageError
        return respond_store_update_error(
          @store.errors.full_messages,
          status: :conflict,
          code: "image_pair_stale"
        )
      rescue Stores::UpdateService::ImageUploadError
        return respond_store_update_error(
          @store.errors.full_messages,
          status: :service_unavailable,
          code: "image_upload_failed",
          retryable: true
        )
      rescue ActiveRecord::RecordInvalid, Stores::UpdateService::Error
        return respond_store_update_error(@store.errors.full_messages)
      rescue ActionController::ParameterMissing, ImageAttachments::MultipartPayload::Invalid => error
        @store.errors.add(:base, error.message)
        return respond_store_update_error(@store.errors.full_messages)
      end

      respond_to do |format|
        format.html { redirect_to store_edit_return_path, notice: "店舗情報を更新しました" }
        format.json do
          flash[:notice] = "店舗情報を更新しました"
          render json: { state: "complete", redirect_url: store_edit_return_path }
        end
      end
    end

    private

    def image_pair_payload
      return nil if params.dig(:image_pair, :operation).blank?

      ImageAttachments::MultipartPayload.from_params(params)
    rescue TypeError
      raise ImageAttachments::MultipartPayload::Invalid, "画像送信パラメータが不正です。"
    end

    def render_selection_conflict_form(message)
      @store.assign_attributes(store_params.except(:thumbnail, :remove_thumbnail))
      @store.errors.add(:base, message)
      render :edit, status: :conflict
    end

    def load_selectable_stores
      @stores = current_selection.stores
      @current_store_id = current_store&.id
      @return_to = params[:return_to].presence
      @return_to_key = params[:return_to_key].presence
    end

    def set_store
      @store = Store.find(params[:id])
      @edit_return_to = "store_detail" if params[:return_to] == "store_detail"
    end

    def store_edit_return_path
      return store_path(@store) if @edit_return_to == "store_detail" && @store.published?

      dashboard_path
    end

    def authorize_store_edit!
      return if current_user.system_admin?

      ok = StoreMembership.admin_only.exists?(user_id: current_user.id, store_id: @store.id)
      head :forbidden unless ok
    end

    def store_params
      permitted_attributes = [
        :name,
        :description,
        :area,
        :business_type,
        :address,
        :phone_number,
        :business_hours,
        :website_url,
        :x_url,
        :instagram_url,
        :tiktok_url,
        :youtube_url,
        :published,
        :thumbnail,
        :remove_thumbnail
      ]
      permitted_attributes << :sales_support_company if current_user.system_admin?

      params.require(:store).permit(*permitted_attributes)
    end

    def proxy_store_params
      params.require(:proxy_store_registration).permit(:store_name, :referral_code)
    end

    def require_store_registration_proxy!
      return if current_user.store_registration_proxy_allowed?

      head :forbidden
    end

    def respond_store_update_error(
      messages,
      status: :unprocessable_entity,
      code: "store_update_invalid",
      retryable: false
    )
      message = messages.join(" / ")

      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = message

          render turbo_stream: turbo_stream.update(
            "flash_inner",
            partial: "shared/flash_message",
            locals: { level: "danger", message: flash.now[:alert] }
          ), status: :unprocessable_entity
        end

        format.html do
          redirect_to edit_admin_store_path(@store, return_to: @edit_return_to), alert: message
        end

        format.json do
          render json: { error: code, message:, retryable: }, status:
        end
      end
    end
  end
end
