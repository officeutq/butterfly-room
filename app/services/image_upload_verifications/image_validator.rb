# frozen_string_literal: true

module ImageUploadVerifications
  # Compatibility adapter for the verification-only upload flow. Production
  # uploads and migration batches use ImageAttachments::PairValidator directly.
  class ImageValidator
    Purpose = Data.define(:ratio_key, :output_width, :output_height)

    Invalid = ImageAttachments::PairValidator::Invalid
    BYTE_LIMITS = ImageAttachments::PairValidator::BYTE_LIMITS.transform_keys(&:to_s).freeze
    OUTPUTS = ImageAttachments::PairValidator::OUTPUTS

    def self.crop!(data)
      validator(data).crop_data!(data)
    end

    def self.call(file, role:, crop_data:)
      validator(crop_data).image!(file, role:, crop_data:)
    end

    def self.validator(data)
      ratio_key = data["ratioKey"] if data.is_a?(Hash)
      width, height = OUTPUTS.fetch(ratio_key) do
        raise Invalid, "未対応のクロップ情報です。"
      end
      ImageAttachments::PairValidator.new(
        purpose: Purpose.new(ratio_key:, output_width: width, output_height: height)
      )
    end
    private_class_method :validator
  end
end
