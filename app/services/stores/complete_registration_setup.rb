# frozen_string_literal: true

module Stores
  class CompleteRegistrationSetup
    def initialize(
      store:,
      attributes:,
      image_update: nil,
      update_service: Stores::UpdateService,
      completion_service: LpAnalytics::Completions::RecordService,
      logger: Rails.logger
    )
      @store = store
      @attributes = attributes.to_h.symbolize_keys.except(:published, :sales_support_company)
      @image_update = image_update
      @update_service = update_service
      @completion_service = completion_service
      @logger = logger
    end

    def call
      @update_service.new(
        store: @store,
        attributes: @attributes.merge(published: true),
        image_update: @image_update
      ).call

      record_completion
      @store
    end

    private

    def record_completion
      visit = @store.lp_analytics_visit
      return if visit.blank?

      @completion_service.new(
        visit:,
        event_type: "store_registration_complete",
        completion_record: @store
      ).call
    rescue StandardError => error
      @logger.error(
        {
          event: "store_registration_completion_record_failed",
          error_class: error.class.name
        }.to_json
      )
    end
  end
end
