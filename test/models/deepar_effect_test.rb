# frozen_string_literal: true

require "test_helper"

class DeeparEffectTest < ActiveSupport::TestCase
  test "loads enabled effects from config in position order" do
    effects = DeeparEffect.enabled

    assert effects.size >= 7
    assert_equal "deepar_aviators", effects.first.key
    assert_equal "/deepar/effects/aviators", effects.first.url
    assert_equal "deepar_effects/aviators_preview.svg", effects.first.preview_path
  end

  test "returns configured default effect" do
    default = DeeparEffect.default

    assert_equal "deepar_aviators", default.key
    assert_predicate default, :default?
  end
end
