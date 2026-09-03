# frozen_string_literal: true

module ImageUploadVerifications
  class CleanupService
    def call
      ImageUploadVerificationRun.where(cleanup_after: ..Time.current).limit(100).each do |run|
        cleanup(run)
      rescue StandardError => error
        # Keep the record and references on storage failure; retry next sweep.
        Rails.logger.error("[ImageUploadVerifications] cleanup failed run=#{run.id} error=#{error.class.name}")
      end
    end

    private

    def cleanup(run)
      run.with_lock do
        blobs = [ run.source_blob, run.display_blob ].compact
        unless blobs.all? { |blob| blob.key.start_with?("#{UploadService::KEY_PREFIX}#{run.id}/") && !blob.attachments.exists? }
          raise "verification cleanup refused an unrelated or attached blob"
        end
        # Delete storage first, DB last: failures remain retryable. Never sweep
        # all unattached blobs. Only this verification run's owned keys qualify.
        blobs.each { |blob| blob.service.delete(blob.key) }
        run.update!(source_blob: nil, display_blob: nil)
        blobs.each(&:destroy!)
        run.destroy!
      end
    end
  end
end
