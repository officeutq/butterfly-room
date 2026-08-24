# frozen_string_literal: true

require "test_helper"

class Stores::AiAutofill::SettingsTest < ActiveSupport::TestCase
  test "requires an API key" do
    assert_raises(Stores::AiAutofill::Settings::ConfigurationError) do
      Stores::AiAutofill::Settings.from_env({ "OPENAI_API_KEY" => "  " })
    end
  end

  test "uses the default model when the model setting is blank" do
    settings = Stores::AiAutofill::Settings.from_env(
      "OPENAI_API_KEY" => "secret",
      "OPENAI_STORE_AUTOFILL_MODEL" => " "
    )

    assert_equal "secret", settings.api_key
    assert_equal "gpt-5.6-terra", settings.model
  end

  test "uses the configured model" do
    settings = Stores::AiAutofill::Settings.from_env(
      "OPENAI_API_KEY" => "secret",
      "OPENAI_STORE_AUTOFILL_MODEL" => "configured-model"
    )

    assert_equal "configured-model", settings.model
  end
end
