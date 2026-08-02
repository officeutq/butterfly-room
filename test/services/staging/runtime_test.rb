# frozen_string_literal: true

require "test_helper"

class StagingRuntimeTest < ActiveSupport::TestCase
  test "GTM defaults off in staging and on elsewhere" do
    assert_not Staging::Runtime.gtm_enabled?({ "APP_ENV" => "staging" })
    assert Staging::Runtime.gtm_enabled?({ "APP_ENV" => "production" })
  end

  test "GTM can be explicitly enabled" do
    assert Staging::Runtime.gtm_enabled?({ "APP_ENV" => "staging", "GTM_ENABLED" => "true" })
  end

  test "unknown boolean values use the fail-closed default" do
    env = { "BASIC_AUTH_ENABLED" => "typo" }

    assert Staging::Runtime.enabled?("BASIC_AUTH_ENABLED", default: true, env: env)
    assert_not Staging::Runtime.enabled?("GTM_ENABLED", default: false, env: { "GTM_ENABLED" => "typo" })
  end
end
