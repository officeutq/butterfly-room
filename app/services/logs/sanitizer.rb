# frozen_string_literal: true

module Logs
  class Sanitizer
    FILTERED = "[FILTERED]"
    FIELDS = {
      "Store" => %w[name description area business_type address phone_number business_hours website_url x_url instagram_url tiktok_url youtube_url published sales_support_company thumbnail],
      "Booth" => %w[name description thumbnail]
    }.freeze
    PRIVATE_FIELDS = %w[description address phone_number business_hours website_url x_url instagram_url tiktok_url youtube_url].freeze

    def self.identifier(value)
      string = value.to_s
      string if string.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
    end

    def self.class_name(value)
      string = value.to_s
      string if string.length <= 200 && string.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
    end

    def self.positive_id(value)
      number = Integer(value, exception: false)
      number if number && number.positive? && number <= 9_223_372_036_854_775_807
    end

    def self.change_data(target_type, changes)
      raise ArgumentError, "invalid change data" unless changes.is_a?(Hash)

      allowed = FIELDS.fetch(target_type, [])
      changes.each_with_object({}) do |(key, pair), output|
        key = key.to_s
        next unless allowed.include?(key)
        raise ArgumentError, "invalid change pair" unless pair.is_a?(Array) && pair.size == 2

        output[key] = pair.map { |value| change_value(key, value) }
      end
    end

    def self.change_value(key, value)
      return nil if value.nil?
      return FILTERED if PRIVATE_FIELDS.include?(key)
      if key == "thumbnail"
        raise ArgumentError, "invalid image identifiers" unless value.is_a?(Hash)

        return value.stringify_keys.slice("source_blob_id", "display_blob_id").transform_values { |id| positive_id(id) }
      end
      return value if value == true || value == false || value.is_a?(Numeric)
      raise ArgumentError, "invalid change value" unless value.is_a?(String)

      value.scrub.gsub(/[[:cntrl:]]/, " ").truncate(1000)
    end

    def self.backtrace(error)
      root = Regexp.escape("#{Rails.root}/")
      Array(error.backtrace).filter_map do |line|
        match = line.match(/\A(?:#{root})?((?:app|lib)\/[a-zA-Z0-9_\/.\-]+\.rb):(\d+)/)
        "#{match[1]}:#{match[2]}" if match && match[1].length <= 230
      end.first(30)
    end
  end
end
