# frozen_string_literal: true

require "test_helper"

class DeeparEffectTest < ActiveSupport::TestCase
  test "loads only enabled effects from config" do
    effects = DeeparEffect.enabled

    assert_equal enabled_config_rows.map { |row| row.fetch("key").to_s }.sort,
                 effects.map(&:key).sort
  end

  test "loads enabled effects from config in position order" do
    effects = DeeparEffect.enabled

    assert_equal ordered_enabled_config_rows.map { |row| row.fetch("key").to_s },
                 effects.map(&:key)
  end

  test "returns configured default effect" do
    default = DeeparEffect.default

    assert_equal expected_default_config_row.fetch("key").to_s, default.key
    assert_equal boolean(expected_default_config_row.fetch("default", false)), default.default?
  end

  private

  def config_rows
    rows = YAML.safe_load_file(DeeparEffect::CONFIG_PATH, aliases: true) || []

    Array(rows).map.with_index do |attrs, index|
      attrs.to_h.stringify_keys.merge("fallback_position" => index)
    end
  end

  def enabled_config_rows
    config_rows.select { |row| boolean(row.fetch("enabled", true)) }
  end

  def ordered_enabled_config_rows
    enabled_config_rows.sort_by do |row|
      [ Integer(row.fetch("position", row.fetch("fallback_position"))), row.fetch("key").to_s ]
    end
  end

  def expected_default_config_row
    ordered_enabled_config_rows.find { |row| boolean(row.fetch("default", false)) } ||
      ordered_enabled_config_rows.first
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
