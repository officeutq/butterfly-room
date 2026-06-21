# frozen_string_literal: true

require "yaml"

class DeeparEffect
  CONFIG_PATH = Rails.root.join("config/deepar_effects.yml")
  PREVIEW_ASSET_PREFIX = "deepar_effects"

  attr_reader :key, :name, :url, :preview_filename, :position

  def self.enabled
    all.select(&:enabled?).sort_by { |effect| [effect.position, effect.key] }
  end

  def self.default(effects = enabled)
    effects.find(&:default?) || effects.first
  end

  def self.all
    rows = YAML.safe_load(
      File.read(CONFIG_PATH),
      aliases: true
    ) || []

    Array(rows).map.with_index do |attrs, index|
      new(attrs, fallback_position: index)
    end
  end

  def initialize(attrs, fallback_position:)
    attrs = attrs.to_h.stringify_keys

    @key = attrs.fetch("key").to_s
    @name = attrs.fetch("name", @key).to_s
    @url = attrs.fetch("url").to_s
    @preview_filename = attrs["preview_filename"].to_s
    @position = Integer(attrs.fetch("position", fallback_position))
    @enabled = attrs.fetch("enabled", true)
    @default = attrs.fetch("default", false)
  end

  def enabled?
    ActiveModel::Type::Boolean.new.cast(@enabled)
  end

  def default?
    ActiveModel::Type::Boolean.new.cast(@default)
  end

  def preview_path
    return nil if preview_filename.blank?
    return preview_filename if preview_filename.include?("/")

    "#{PREVIEW_ASSET_PREFIX}/#{preview_filename}"
  end
end
