# frozen_string_literal: true

module ImageAttachments
  class StagedBlobCleanupService
    DEFAULT_BATCH_SIZE = 100
    MAX_BATCH_SIZE = 1_000

    Result = Data.define(:inspected, :purged, :skipped)

    class CleanupError < StandardError; end

    def initialize(
      now: Time.current,
      batch_size: DEFAULT_BATCH_SIZE,
      relation: ActiveStorage::Blob.all,
      purger: StagedBlobPurgeService
    )
      @now = now
      @batch_size = Integer(batch_size)
      @relation = relation
      @purger = purger
      unless @batch_size.between?(1, MAX_BATCH_SIZE)
        raise ArgumentError, "batch_size must be between 1 and #{MAX_BATCH_SIZE}"
      end
    rescue TypeError, ArgumentError
      raise ArgumentError, "batch_size must be between 1 and #{MAX_BATCH_SIZE}"
    end

    def call
      inspected = 0
      purged = 0
      skipped = 0
      failures = []

      candidates.each do |blob|
        inspected += 1
        unless StagedBlobMetadata.expired?(blob, at: @now)
          skipped += 1
          next
        end

        @purger.new(blob:).call ? purged += 1 : skipped += 1
      rescue StandardError => error
        failures << blob.id
        Rails.logger.error(
          "[ImageAttachments::StagedBlobCleanupService] cleanup failed " \
          "blob=#{blob.id} error=#{error.class.name}"
        )
      end

      if failures.any?
        raise CleanupError, "failed to clean #{failures.length} staged image blob(s)"
      end

      Result.new(inspected:, purged:, skipped:)
    end

    private

    def candidates
      @relation
        .where("metadata LIKE ?", "%#{StagedBlobMetadata::MARKER_KEY}%")
        .order(:id)
        .limit(@batch_size)
    end
  end
end
