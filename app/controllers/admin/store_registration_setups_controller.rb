# frozen_string_literal: true

module Admin
  class StoreRegistrationSetupsController < Admin::BaseController
    before_action :load_and_authorize_registration_store!

    def edit; end

    def update
      Stores::CompleteRegistrationSetup.new(
        store: @store,
        attributes: store_information_params,
        image_update: image_pair_payload
      ).call

      complete_registration_session!
      respond_registration_setup_success
    rescue Stores::UpdateService::StaleImageError
      respond_registration_setup_error(
        status: :conflict,
        code: "image_pair_stale"
      )
    rescue Stores::UpdateService::ImageUploadError
      respond_registration_setup_error(
        status: :service_unavailable,
        code: "image_upload_failed",
        retryable: true
      )
    rescue ActiveRecord::RecordInvalid, Stores::UpdateService::Error
      respond_registration_setup_error
    rescue ActionController::ParameterMissing, ImageAttachments::MultipartPayload::Invalid => error
      @store.errors.add(:base, error.message)
      respond_registration_setup_error
    end

    private

    def load_and_authorize_registration_store!
      @registration_pending = session[STORE_REGISTRATION_PENDING_SESSION_KEY]
      route_store_id = strict_integer(params[:store_id])
      pending_store_id = strict_integer(session_value(@registration_pending, "store_id"))
      current_store_id = strict_integer(session[:current_store_id])
      @store = Store.find_by(id: route_store_id)

      return if valid_registration_store?(pending_store_id:, current_store_id:)

      redirect_to invalid_registration_setup_redirect_path,
                  alert: "初回店舗設定を確認できませんでした。店舗設定から編集してください。"
    end

    def valid_registration_store?(pending_store_id:, current_store_id:)
      return false if @registration_pending.blank? || @store.blank?
      return false unless pending_store_id == @store.id && current_store_id == @store.id
      return true if current_user.system_admin?

      admin_membership_exists_for_store?(@store.id)
    end

    def strict_integer(value)
      Integer(value, exception: false)
    end

    def session_value(payload, key)
      return unless payload.respond_to?(:[])

      payload[key].presence || payload[key.to_sym].presence
    end

    def invalid_registration_setup_redirect_path
      selected_store = current_store
      return edit_admin_store_path(selected_store) if selected_store.present?

      dashboard_path
    end

    def store_information_params
      params.require(:store).permit(
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
        :youtube_url
      )
    end

    def image_pair_payload
      return nil if params.dig(:image_pair, :operation).blank?

      ImageAttachments::MultipartPayload.from_params(params)
    rescue TypeError
      raise ImageAttachments::MultipartPayload::Invalid, "画像送信パラメータが不正です。"
    end

    def complete_registration_session!
      completion = {
        "store_id" => @store.id
      }
      from = session_value(@registration_pending, "from")
      utm = session_value(@registration_pending, "utm")
      completion["from"] = from if from.present?
      completion["utm"] = utm if utm.present?

      session[STORE_REGISTRATION_COMPLETION_SESSION_KEY] = completion
      session.delete(STORE_REGISTRATION_PENDING_SESSION_KEY)
    end

    def respond_registration_setup_success
      destination = stores_registration_thanks_path

      respond_to do |format|
        format.html { redirect_to destination }
        format.json { render json: { state: "complete", redirect_url: destination } }
      end
    end

    def respond_registration_setup_error(
      status: :unprocessable_entity,
      code: "store_registration_setup_invalid",
      retryable: false
    )
      messages = @store.errors.full_messages
      message = messages.join(" / ")

      respond_to do |format|
        format.turbo_stream { render :edit, formats: :html, status: }
        format.html { render :edit, status: }
        format.json do
          render json: { error: code, message:, retryable: }, status:
        end
      end
    end
  end
end
