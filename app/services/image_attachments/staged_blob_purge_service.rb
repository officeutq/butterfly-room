# frozen_string_literal: true

module ImageAttachments
  class StagedBlobPurgeService
    class RefusedError < StandardError; end

    def initialize(blob:)
      @blob = blob
    end

    def call
      purged = false
      @blob.with_lock do
        next if @blob.attachments.exists?

        unless StagedBlobMetadata.owned?(@blob)
          raise RefusedError, "blob is not owned by image attachment staging"
        end

        # Delete storage first so a storage failure leaves the Blob row and its
        # cleanup metadata available for the next sweep.
        @blob.delete
        @blob.destroy!
        purged = true
      end
      purged
    rescue ActiveRecord::RecordNotFound
      false
    end
  end
end
