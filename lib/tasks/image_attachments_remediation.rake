# frozen_string_literal: true

require "json"

module ImageAttachmentsRemediationTask
  module_function

  def call(environment = ENV)
    options = remediation_options(environment)
    validate_confirmation!(environment, options) if options.fetch(:apply)

    result = ImageAttachments::RemediateService.new(**options).call
    JSON.generate(event: "image_attachment_remediation_result", **result.to_h)
  end

  def failure_payload(error, environment = ENV)
    {
      event: "image_attachment_remediation_result",
      dry_run: !apply_requested?(environment),
      status: "failed",
      error_class: error.class.name
    }
  end

  def remediation_options(environment)
    {
      record_type: required_value(environment, "RECORD_TYPE"),
      record_id: required_value(environment, "RECORD_ID"),
      attachment_name: required_value(environment, "ATTACHMENT_NAME"),
      expected_attachment_id: required_value(environment, "EXPECTED_ATTACHMENT_ID"),
      expected_blob_id: required_value(environment, "EXPECTED_BLOB_ID"),
      apply: boolean_value(environment, "APPLY")
    }
  end

  def validate_confirmation!(environment, options)
    expected = confirmation_value(options)
    actual = optional_value(environment, "CONFIRM")
    return if actual == expected

    raise ArgumentError, "#{environment_key('CONFIRM')} must be #{expected} when apply is enabled"
  end

  def confirmation_value(options)
    [
      options.fetch(:record_type),
      options.fetch(:record_id),
      options.fetch(:attachment_name),
      options.fetch(:expected_attachment_id),
      options.fetch(:expected_blob_id)
    ].join(":")
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

  def required_value(environment, name)
    optional_value(environment, name) || raise(ArgumentError, "#{environment_key(name)} is required")
  end

  def optional_value(environment, name)
    value = environment[environment_key(name)].to_s.strip
    value unless value.empty?
  end

  def environment_key(name)
    "IMAGE_REMEDIATION_#{name}"
  end
end

namespace :image_attachments do
  desc "Dry-run or apply remediation for one inventoried display image attachment"
  task remediate: :environment do
    puts ImageAttachmentsRemediationTask.call
  rescue ArgumentError, ImageAttachments::RemediateService::Error => error
    puts JSON.generate(ImageAttachmentsRemediationTask.failure_payload(error))
    abort "[ImageAttachmentRemediation] #{error.message}"
  end
end
