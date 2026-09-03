# frozen_string_literal: true

# Temporary verification data only; never attached to a production image field.
class ImageUploadVerificationRun < ApplicationRecord
  belongs_to :user
  belongs_to :source_blob, class_name: "ActiveStorage::Blob", optional: true
  belongs_to :display_blob, class_name: "ActiveStorage::Blob", optional: true

  validates :transport, inclusion: { in: %w[multipart direct] }
  validates :state, inclusion: { in: %w[pending uploading verifying complete canceled failed] }
  validates :expires_at, :cleanup_after, presence: true
end
