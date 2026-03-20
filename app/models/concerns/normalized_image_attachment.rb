# frozen_string_literal: true

require "mini_magick"
require "tempfile"

module NormalizedImageAttachment
  extend ActiveSupport::Concern

  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze

  class InvalidImageAttachment < StandardError; end

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

    claimed_content_type = extract_attachable_content_type(attachable)

    unless NormalizedImageAttachment::ALLOWED_CONTENT_TYPES.include?(claimed_content_type)
      raise InvalidImageAttachment, "は png / jpg / webp のみアップロードできます"
    end

    image = MiniMagick::Image.open(extract_attachable_path(attachable))
    actual_type = image.type.to_s.upcase

    actual_content_type =
      case actual_type
      when "JPEG"
        "image/jpeg"
      when "PNG"
        "image/png"
      when "WEBP"
        "image/webp"
      else
        nil
      end

    if actual_content_type.blank?
      raise InvalidImageAttachment, "は png / jpg / webp のみアップロードできます"
    end

    image.auto_orient

    return attachable if image.width <= max_width && image.height <= max_height

    output_content_type = actual_content_type
    output_extension = filename_extension_for(output_content_type)

    tempfile = Tempfile.new([ "normalized-image", output_extension ])
    tempfile.binmode

    image.resize("#{max_width}x#{max_height}>")

    case output_content_type
    when "image/jpeg"
      image.format("jpg")
    when "image/png"
      image.format("png")
    when "image/webp"
      image.format("webp")
    end

    image.write(tempfile.path)
    tempfile.rewind

    {
      io: tempfile,
      filename: "#{File.basename(extract_attachable_filename(attachable), ".*")}#{output_extension}",
      content_type: output_content_type
    }
  rescue MiniMagick::Error, MiniMagick::Invalid => e
    Rails.logger.error(
      "[NormalizedImageAttachment] normalize failed: " \
      "class=#{e.class} message=#{e.message} " \
      "filename=#{extract_attachable_filename(attachable)} " \
      "claimed_content_type=#{extract_attachable_content_type(attachable)}"
    )

    raise InvalidImageAttachment, "の処理に失敗しました。png / jpg / webp の画像で再度お試しください"
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
