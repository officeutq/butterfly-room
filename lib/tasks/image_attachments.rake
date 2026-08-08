# frozen_string_literal: true

require "json"

module ImageAttachmentsInventoryTask
  module_function

  def call(environment = ENV)
    result = ImageAttachments::InventoryService.new(
      inspect_all: boolean_value(environment, "INSPECT_ALL"),
      limit: optional_value(environment, "LIMIT"),
      after_attachment_id: optional_value(environment, "AFTER_ATTACHMENT_ID"),
      record_type: optional_value(environment, "RECORD_TYPE"),
      record_id: optional_value(environment, "RECORD_ID")
    ).call

    [
      JSON.generate(summary_payload(result)),
      *result.entries.map { |entry| JSON.generate(entry_payload(entry)) }
    ]
  end

  def summary_payload(result)
    {
      event: "image_attachment_inventory_summary",
      dry_run: true,
      selection: result.selection,
      limit: result.limit,
      after_attachment_id: result.after_attachment_id,
      last_attachment_id: result.last_attachment_id,
      target_count: result.target_count,
      metadata_candidate_count: result.metadata_candidate_count,
      inspected_count: result.inspected_count,
      status_counts: result.status_counts
    }
  end

  def entry_payload(entry)
    {
      event: "image_attachment_inventory_entry",
      dry_run: true,
      **entry.to_h
    }
  end

  def boolean_value(environment, name)
    value = optional_value(environment, name)
    return false if value.nil?

    normalized = value.downcase
    return true if %w[1 true].include?(normalized)
    return false if %w[0 false].include?(normalized)

    raise ArgumentError, "#{environment_key(name)} must be true, false, 1, or 0"
  end

  def optional_value(environment, name)
    value = environment[environment_key(name)].to_s.strip
    value unless value.empty?
  end

  def environment_key(name)
    "IMAGE_INVENTORY_#{name}"
  end
end

namespace :image_attachments do
  desc "Dry-run inventory of Store, Booth, and User display image attachments"
  task inventory: :environment do
    ImageAttachmentsInventoryTask.call.each { |line| puts line }
  rescue ArgumentError => error
    abort "[ImageAttachmentInventory] #{error.message}"
  end
end
