# frozen_string_literal: true

require "mini_magick"
require "tempfile"

module NormalizedImageAttachment
  extend ActiveSupport::Concern

  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze

  class_methods do
    def normalizes_image_attachment(name, max_width: 1024, max_height: 1024)
      validate do
        attachment = public_send(name)
        next unless attachment.attached?

        content_type = attachment.blob.content_type.to_s
        next if NormalizedImageAttachment::ALLOWED_CONTENT_TYPES.include?(content_type)

        errors.add(name, "は png / jpg / webp のみアップロードできます")
      end

      define_method("#{name}=") do |attachable|
        normalized =
          normalize_image_attachment_attachable(
            attachable,
            max_width: max_width,
            max_height: max_height
          )

        super(normalized)
      end
    end
  end

  private

  def normalize_image_attachment_attachable(attachable, max_width:, max_height:)
    return attachable if attachable.blank?
    return attachable unless uploaded_file_attachable?(attachable)

    content_type = extract_attachable_content_type(attachable)
    return attachable unless NormalizedImageAttachment::ALLOWED_CONTENT_TYPES.include?(content_type)

    image = MiniMagick::Image.open(extract_attachable_path(attachable))
    return attachable if image.width <= max_width && image.height <= max_height

    image.auto_orient
    image.resize("#{max_width}x#{max_height}>")

    tempfile = Tempfile.new([ "normalized-image", filename_extension_for(content_type) ])
    tempfile.binmode
    image.write(tempfile.path)
    tempfile.rewind

    {
      io: tempfile,
      filename: extract_attachable_filename(attachable),
      content_type: content_type
    }
  rescue MiniMagick::Error, MiniMagick::Invalid
    attachable
  end

  def uploaded_file_attachable?(attachable)
    attachable.respond_to?(:tempfile) &&
      attachable.respond_to?(:original_filename) &&
      attachable.respond_to?(:content_type)
  end

  def extract_attachable_path(attachable)
    attachable.tempfile.path
  end

  def extract_attachable_filename(attachable)
    attachable.original_filename.to_s
  end

  def extract_attachable_content_type(attachable)
    attachable.content_type.to_s
  end

  def filename_extension_for(content_type)
    case content_type
    when "image/png"
      ".png"
    when "image/webp"
      ".webp"
    else
      ".jpg"
    end
  end
end
