# frozen_string_literal: true

require "digest"

module LpAnalytics
  class EventsController < ApplicationController
    MAX_REQUEST_BYTES = 16.kilobytes

    skip_before_action :authenticate_user!
    prepend_before_action :reject_oversized_request, :require_same_origin
    rate_limit to: 120, within: 1.minute, by: :rate_limit_identity, only: :create

    def create
      attributes = event_params
      browser_event_id = attributes.fetch(:event_id)
      raise ActionController::ParameterMissing, :event_id if browser_event_id.blank?

      visit = Visit.find_by_public_id(lp_analytics_visit_public_id)
      raise Events::RecordService::InvalidEventError unless visit

      result = Events::RecordService.new(
        visit: visit,
        event_type: attributes[:event_type],
        event_value: attributes[:event_value],
        browser_event_id: browser_event_id,
        metadata: attributes[:metadata] || {}
      ).call

      render(
        json: { recorded: true, duplicate: result.duplicate },
        status: result.duplicate ? :ok : :created
      )
    rescue ActionController::ParameterMissing, Events::RecordService::InvalidEventError,
           ActiveRecord::RecordInvalid
      render json: { recorded: false }, status: :unprocessable_entity
    end

    private

    def event_params
      params
        .require(:lp_analytics_event)
        .permit(:event_id, :event_type, :event_value, metadata: {})
    end

    def reject_oversized_request
      head 413 if request.content_length.to_i > MAX_REQUEST_BYTES
    end

    def require_same_origin
      return if request.origin.blank? || request.origin == request.base_url

      head :forbidden
    end

    def rate_limit_identity
      raw_identity = lp_analytics_visit_public_id.presence || request.session.id.to_s
      Digest::SHA256.hexdigest(raw_identity.presence || "unresolved")
    end
  end
end
