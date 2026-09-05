# frozen_string_literal: true

module ImageAttachments
  class StagedBlobCleanupJob < ApplicationJob
    queue_as :default

    def perform
      cleanup_service.call
    end

    private

    def cleanup_service
      StagedBlobCleanupService.new
    end
  end
end
