# frozen_string_literal: true

require "time"

module ImageAttachments
  class StagedBlobMetadata
    MARKER_KEY = "image_attachment_staging"
    SCHEMA_VERSION = 1
    DEFAULT_TTL = 1.hour
    ROLES = %w[source display].freeze

    class << self
      def build(existing_metadata: {}, purpose:, role:, cleanup_after: DEFAULT_TTL.from_now)
        metadata = existing_metadata.to_h.deep_stringify_keys
        metadata.merge(
          MARKER_KEY => {
            "schemaVersion" => SCHEMA_VERSION,
            "purpose" => purpose_name!(purpose),
            "role" => role_name!(role),
            "cleanupAfter" => cleanup_time!(cleanup_after).utc.iso8601(6)
          }
        )
      end

      def mark!(blob, purpose:, role:, cleanup_after: DEFAULT_TTL.from_now)
        raise ArgumentError, "staged blob must be unattached" if blob.attachments.exists?

        blob.update!(metadata: build(existing_metadata: blob.metadata, purpose:, role:, cleanup_after:))
        blob
      end

      def owned?(blob, purpose: nil, role: nil)
        marker = marker_for(blob)
        return false unless marker["schemaVersion"] == SCHEMA_VERSION
        return false unless valid_purpose_name?(marker["purpose"])
        return false unless ROLES.include?(marker["role"])
        return false unless cleanup_time(marker["cleanupAfter"])
        return false if purpose && marker["purpose"] != purpose_name!(purpose)
        return false if role && marker["role"] != role_name!(role)

        true
      rescue ArgumentError
        false
      end

      def expired?(blob, at: Time.current)
        return false unless owned?(blob)

        cleanup_time(marker_for(blob)["cleanupAfter"]) <= at
      end

      def active?(blob, purpose:, role:, at: Time.current)
        owned?(blob, purpose:, role:) && !expired?(blob, at:)
      end

      def clear!(blob)
        blob.update!(metadata: blob.metadata.to_h.deep_stringify_keys.except(MARKER_KEY))
        blob
      end

      private

      def marker_for(blob)
        blob.metadata.to_h.deep_stringify_keys.fetch(MARKER_KEY, {})
      end

      def purpose_name!(purpose)
        name = purpose.respond_to?(:name) ? purpose.name.to_s : purpose.to_s
        raise ArgumentError, "invalid image attachment purpose" unless valid_purpose_name?(name)

        name
      end

      def valid_purpose_name?(name)
        name.is_a?(String) && name.match?(/\A[a-z][a-z0-9_]{0,63}\z/)
      end

      def role_name!(role)
        name = role.to_s
        raise ArgumentError, "invalid staged blob role" unless ROLES.include?(name)

        name
      end

      def cleanup_time!(value)
        value.respond_to?(:to_time) ? value.to_time : Time.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        raise ArgumentError, "invalid staged blob cleanup time"
      end

      def cleanup_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
