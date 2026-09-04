# frozen_string_literal: true

module ImageAttachmentPurposes
  extend ActiveSupport::Concern

  Configuration = Data.define(
    :name,
    :source_attachment,
    :display_attachment,
    :crop_attribute,
    :ratio_key,
    :output_width,
    :output_height
  )

  included do
    class_attribute :image_attachment_purposes,
      instance_accessor: false,
      default: {}
  end

  class_methods do
    def image_attachment_purpose(
      name,
      source_attachment:,
      display_attachment:,
      crop_attribute:,
      ratio_key:,
      output_width:,
      output_height:
    )
      purpose_name = name.to_sym
      configuration = Configuration.new(
        name: purpose_name,
        source_attachment: source_attachment.to_sym,
        display_attachment: display_attachment.to_sym,
        crop_attribute: crop_attribute.to_sym,
        ratio_key: ratio_key.to_s,
        output_width: Integer(output_width),
        output_height: Integer(output_height)
      )

      self.image_attachment_purposes = image_attachment_purposes.merge(purpose_name => configuration).freeze
    end

    def image_attachment_purpose_for(name)
      image_attachment_purposes.fetch(name.to_sym)
    rescue KeyError
      raise ArgumentError, "unknown image attachment purpose: #{name}"
    end
  end

  def image_attachment_purpose_for(name)
    self.class.image_attachment_purpose_for(name)
  end
end
