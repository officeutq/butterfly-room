# frozen_string_literal: true

require "json"
require "time"

module ImageAttachmentsLegacyMigrationTask
  module_function

  def call(environment = ENV)
    started_at = Time.current
    options = migration_options(environment)
    git_commit = git_commit_value(environment, required: options.fetch(:apply))
    result = ImageAttachments::LegacyMigrationService.new(**options).call
    finished_at = Time.current

    [
      JSON.generate(summary_payload(result, git_commit:, started_at:, finished_at:)),
      *result.entries.map { |entry| JSON.generate(entry_payload(entry, result:)) }
    ]
  end

  def summary_payload(result, git_commit:, started_at:, finished_at:)
    {
      event: "legacy_image_pair_migration_summary",
      schema_version: 1,
      dry_run: result.dry_run,
      git_commit:,
      started_at: started_at.utc.iso8601(6),
      finished_at: finished_at.utc.iso8601(6),
      record_type: result.record_type,
      record_id: result.record_id,
      min_attachment_id: result.min_attachment_id,
      max_attachment_id: result.max_attachment_id,
      after_attachment_id: result.after_attachment_id,
      limit: result.limit,
      target_count: result.target_count,
      selected_count: result.selected_count,
      last_attachment_id: result.last_attachment_id,
      status_counts: result.status_counts
    }
  end

  def entry_payload(entry, result:)
    {
      event: "legacy_image_pair_migration_entry",
      schema_version: 1,
      dry_run: result.dry_run,
      **entry.to_h
    }
  end

  def failure_payload(error, environment = ENV)
    {
      event: "legacy_image_pair_migration_failure",
      schema_version: 1,
      dry_run: !apply_requested?(environment),
      status: "failed",
      error_class: error.class.name
    }
  end

  def migration_options(environment)
    {
      apply: boolean_value(environment, "APPLY"),
      confirmation: optional_value(environment, "CONFIRM"),
      record_type: optional_value(environment, "RECORD_TYPE"),
      record_id: optional_value(environment, "RECORD_ID"),
      min_attachment_id: optional_value(environment, "MIN_ATTACHMENT_ID"),
      max_attachment_id: optional_value(environment, "MAX_ATTACHMENT_ID"),
      after_attachment_id: optional_value(environment, "AFTER_ATTACHMENT_ID"),
      limit: optional_value(environment, "LIMIT"),
      expected_attachment_id: optional_value(environment, "EXPECTED_ATTACHMENT_ID"),
      expected_blob_id: optional_value(environment, "EXPECTED_BLOB_ID")
    }
  end

  def git_commit_value(environment, required:)
    value = optional_value(environment, "GIT_COMMIT")
    if value.nil?
      raise ArgumentError, "#{environment_key('GIT_COMMIT')} is required when apply is enabled" if required

      return nil
    end
    return value if value.match?(/\A[0-9a-f]{7,40}\z/)

    raise ArgumentError, "#{environment_key('GIT_COMMIT')} must be a 7-40 character lowercase Git SHA"
  end

  def boolean_value(environment, name)
    value = optional_value(environment, name)
    return false if value.nil?

    normalized = value.downcase
    return true if %w[1 true].include?(normalized)
    return false if %w[0 false].include?(normalized)

    raise ArgumentError, "#{environment_key(name)} must be true, false, 1, or 0"
  end

  def apply_requested?(environment)
    %w[1 true].include?(optional_value(environment, "APPLY")&.downcase)
  end

  def optional_value(environment, name)
    value = environment[environment_key(name)].to_s.strip
    value unless value.empty?
  end

  def environment_key(name)
    "IMAGE_MIGRATION_#{name}"
  end
end

namespace :image_attachments do
  desc "Dry-run or apply the legacy User, Store, and Booth image pair migration"
  task migrate_legacy_pairs: :environment do
    ImageAttachmentsLegacyMigrationTask.call.each { |line| puts line }
  rescue StandardError => error
    puts JSON.generate(ImageAttachmentsLegacyMigrationTask.failure_payload(error))
    abort "[LegacyImagePairMigration] #{error.class.name}: #{error.message}"
  end
end
