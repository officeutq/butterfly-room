# frozen_string_literal: true

module Admin
  class StoreAiAutofillsController < Admin::BaseController
    RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

    before_action :set_store
    before_action :authorize_store_edit!

    rate_limit(
      to: 3,
      within: 10.minutes,
      by: -> { current_user.id },
      with: :render_rate_limited,
      store: RATE_LIMIT_STORE,
      only: :create
    )

    def create
      result = Stores::AiAutofill::SearchService.new(
        store: @store,
        actor: current_user,
        store_name: ai_autofill_params[:store_name]
      ).call

      render json: result.as_json, status: :ok
    rescue Stores::AiAutofill::SearchService::InvalidStoreNameError
      render_feature_error(:unprocessable_entity, "invalid_store_name")
    rescue Stores::AiAutofill::Settings::ConfigurationError
      render_feature_error(:service_unavailable, "configuration_error")
    rescue Stores::AiAutofill::ResponsesClient::RateLimitedError => error
      render_feature_error(:service_unavailable, "openai_rate_limited", error:)
    rescue Stores::AiAutofill::ResponsesClient::TimeoutError => error
      render_feature_error(:gateway_timeout, "timeout", error:)
    rescue Stores::AiAutofill::ResponsesClient::UnavailableError => error
      render_feature_error(:bad_gateway, "openai_unavailable", error:)
    rescue Stores::AiAutofill::ResponsesClient::InvalidResponseError => error
      render_feature_error(:bad_gateway, "invalid_response", error:)
    end

    private

    def set_store
      @store = Store.find(params[:store_id])
    end

    def authorize_store_edit!
      return if current_user.system_admin?
      return if admin_membership_exists_for_store?(@store.id)

      head :forbidden
    end

    def ai_autofill_params
      search_params = params[:store_ai_autofill]
      return ActionController::Parameters.new unless search_params.respond_to?(:permit)

      search_params.permit(:store_name)
    end

    def render_feature_error(status, error_code, error: nil)
      body = { status: "error", error_code: }
      diagnostics = development_diagnostics(error)
      body[:development_diagnostics] = diagnostics if diagnostics.present?

      render json: body, status:
    end

    def render_rate_limited
      render_feature_error(:too_many_requests, "rate_limited")
    end

    def development_diagnostics(error)
      return unless Rails.env.development? && error

      {
        openai_type: diagnostic_value(error, :openai_type),
        openai_code: diagnostic_value(error, :openai_code),
        openai_status: diagnostic_value(error, :openai_status),
        request_id: diagnostic_value(error, :request_id)
      }.compact.presence
    end

    def diagnostic_value(error, attribute)
      return unless error.respond_to?(attribute)

      error.public_send(attribute).to_s.presence&.slice(0, 200)
    end
  end
end
