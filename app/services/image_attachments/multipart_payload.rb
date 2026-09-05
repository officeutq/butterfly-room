# frozen_string_literal: true

require "json"

module ImageAttachments
  # Shared strong-parameter shape and value object for one image-purpose form.
  class MultipartPayload
    PARAM_ROOT = :image_pair
    EXPECTED_ID_KEYS = %w[
      source_attachment_id
      source_blob_id
      display_attachment_id
      display_blob_id
    ].freeze
    PERMITTED_PARAMETERS = [
      :operation,
      :source,
      :display,
      :crop_data,
      { expected: EXPECTED_ID_KEYS.map(&:to_sym) }
    ].freeze
    OPERATIONS = %i[replace reedit delete].freeze
    TOP_LEVEL_KEYS = %w[operation source display crop_data expected].freeze

    class Invalid < StandardError; end

    attr_reader :operation, :source_upload, :display_upload, :crop_data, :expected_snapshot

    def self.from_params(parameters, root: PARAM_ROOT)
      parse(parameters.expect(root => PERMITTED_PARAMETERS).to_h)
    end

    def self.parse(attributes)
      new(attributes).tap(&:validate!)
    end

    def initialize(attributes)
      values = attributes.to_h.stringify_keys
      unless (values.keys - TOP_LEVEL_KEYS).empty?
        raise Invalid, "画像送信パラメータが不正です。"
      end

      @operation = values["operation"]&.to_sym
      @source_upload = values["source"]
      @display_upload = values["display"]
      @crop_data = parse_crop_data(values["crop_data"])
      @expected_snapshot = parse_snapshot(values["expected"])
    rescue NoMethodError
      raise Invalid, "画像送信パラメータが不正です。"
    end

    def validate!
      raise Invalid, "画像操作が不正です。" unless OPERATIONS.include?(@operation)

      case @operation
      when :replace
        require_upload!(@source_upload, "編集元画像")
        require_upload!(@display_upload, "表示用画像")
        require_crop_data!
      when :reedit
        raise Invalid, "再編集では編集元画像を送信しません。" if @source_upload.present?

        require_upload!(@display_upload, "表示用画像")
        require_crop_data!
      when :delete
        if @source_upload.present? || @display_upload.present? || @crop_data.present?
          raise Invalid, "削除では画像・クロップ情報を送信しません。"
        end
      end

      self
    end

    private

    def parse_crop_data(value)
      return nil if value.blank?
      unless value.is_a?(String) && value.bytesize <= PairValidator::MAX_CROP_DATA_BYTES
        raise Invalid, "クロップ情報が不正です。"
      end

      parsed = JSON.parse(value)
      raise Invalid, "クロップ情報が不正です。" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise Invalid, "クロップ情報が不正です。"
    end

    def parse_snapshot(value)
      if value.nil? || !value.respond_to?(:to_h)
        raise Invalid, "編集開始時の画像IDが必要です。"
      end

      values = value.to_h.stringify_keys
      unless (values.keys - EXPECTED_ID_KEYS).empty?
        raise Invalid, "編集開始時の画像IDが不正です。"
      end

      ids = EXPECTED_ID_KEYS.to_h { |key| [ key, optional_positive_integer(values[key]) ] }
      require_id_pair!(ids, "source")
      require_id_pair!(ids, "display")
      StagedPairUpdateService::Snapshot.new(**ids.symbolize_keys)
    end

    def optional_positive_integer(value)
      return nil if value.blank?

      number = case value
      when Integer
        value
      when String
        raise Invalid, "編集開始時の画像IDが不正です。" unless value.match?(/\A[1-9]\d*\z/)

        value.to_i
      else
        raise Invalid, "編集開始時の画像IDが不正です。"
      end
      raise Invalid, "編集開始時の画像IDが不正です。" unless number.positive?

      number
    rescue ArgumentError, TypeError
      raise Invalid, "編集開始時の画像IDが不正です。"
    end

    def require_id_pair!(ids, role)
      attachment_id = ids.fetch("#{role}_attachment_id")
      blob_id = ids.fetch("#{role}_blob_id")
      return if attachment_id.nil? == blob_id.nil?

      raise Invalid, "編集開始時の#{role}画像IDが不完全です。"
    end

    def require_upload!(upload, name)
      unless upload.respond_to?(:tempfile) && upload.tempfile.respond_to?(:path)
        raise Invalid, "#{name}が必要です。"
      end
    end

    def require_crop_data!
      raise Invalid, "クロップ情報が必要です。" unless @crop_data
    end
  end
end
