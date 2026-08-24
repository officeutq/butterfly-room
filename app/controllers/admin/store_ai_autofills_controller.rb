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
        actor: current_user
      ).call

      render json: result.as_json, status: :ok
    rescue Stores::AiAutofill::Settings::ConfigurationError
      render_feature_error(:service_unavailable, "configuration_error")
    rescue Stores::AiAutofill::ResponsesClient::RateLimitedError
      render_feature_error(:service_unavailable, "openai_rate_limited")
    rescue Stores::AiAutofill::ResponsesClient::TimeoutError
      render_feature_error(:gateway_timeout, "timeout")
    rescue Stores::AiAutofill::ResponsesClient::UnavailableError
      render_feature_error(:bad_gateway, "openai_unavailable")
    rescue Stores::AiAutofill::ResponsesClient::InvalidResponseError
      render_feature_error(:bad_gateway, "invalid_response")
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

    def render_feature_error(status, error_code)
      render json: { status: "error", error_code: }, status:
    end

    def render_rate_limited
      render_feature_error(:too_many_requests, "rate_limited")
    end
  end
end
