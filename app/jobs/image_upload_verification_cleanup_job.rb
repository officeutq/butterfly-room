# frozen_string_literal: true

class ImageUploadVerificationCleanupJob < ApplicationJob
  queue_as :default

  def perform
    ImageUploadVerifications::CleanupService.new.call
  end
end
