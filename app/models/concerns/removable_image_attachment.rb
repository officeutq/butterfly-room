# frozen_string_literal: true

module RemovableImageAttachment
  extend ActiveSupport::Concern

  private

  def purge_attachment_if_requested(record:, attachment_name:, remove_param_name:)
    return unless params.dig(record.model_name.param_key, remove_param_name) == "1"
    return if params.dig(record.model_name.param_key, attachment_name).present?

    attachment = record.public_send(attachment_name)
    attachment.purge_later if attachment.attached?
  end
end
