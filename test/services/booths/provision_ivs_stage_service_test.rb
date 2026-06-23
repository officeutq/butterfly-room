# frozen_string_literal: true

require "test_helper"

class Booths::ProvisionIvsStageServiceTest < ActiveSupport::TestCase
  test "manual capture store uses local fake IVS stage outside production" do
    store = Store.create!(name: "マニュアル撮影用店舗")
    booth = Booth.create!(store: store, name: "マニュアル撮影用ブース")
    ivs_client = failing_ivs_client

    arn = Booths::ProvisionIvsStageService.new(
      booth: booth,
      ivs_client: ivs_client,
      rails_env: ActiveSupport::StringInquirer.new("development")
    ).call!

    assert_match %r{\Aarn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local-booth-}, arn
    assert_equal arn, booth.reload.ivs_stage_arn
  end

  test "manual capture fake can be enabled explicitly outside production" do
    store = Store.create!(name: "通常店舗")
    booth = Booth.create!(store: store, name: "通常ブース")
    ivs_client = failing_ivs_client

    with_env("MANUAL_CAPTURE_FAKE_IVS" => "1") do
      arn = Booths::ProvisionIvsStageService.new(
        booth: booth,
        ivs_client: ivs_client,
        rails_env: ActiveSupport::StringInquirer.new("development")
      ).call!

      assert_match %r{\Aarn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local-booth-}, arn
    end
  end

  test "manual capture store still uses real client in production" do
    store = Store.create!(name: "マニュアル撮影用店舗")
    booth = Booth.create!(store: store, name: "マニュアル撮影用ブース")
    ivs_client = fake_ivs_client("arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/REAL")

    arn = Booths::ProvisionIvsStageService.new(
      booth: booth,
      ivs_client: ivs_client,
      rails_env: ActiveSupport::StringInquirer.new("production")
    ).call!

    assert_equal "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/REAL", arn
    assert_equal arn, booth.reload.ivs_stage_arn
  end

  private

  def fake_ivs_client(arn)
    Object.new.tap do |client|
      client.define_singleton_method(:create_stage!) do |name:, tags: {}|
        arn
      end
    end
  end

  def failing_ivs_client
    Object.new.tap do |client|
      client.define_singleton_method(:create_stage!) do |name:, tags: {}|
        raise "IVS client should not be called for manual capture fake"
      end
    end
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
