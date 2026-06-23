# frozen_string_literal: true

namespace :manual_capture do
  desc "Prepare development/test-only data for user manual screenshots"
  task prepare: :environment do
    if Rails.env.production?
      raise "manual_capture:prepare is disabled in production"
    end

    result = ManualCapture::DataBuilder.new.call!

    puts "manual capture data prepared"
    puts "password: #{ManualCapture::DataBuilder::PASSWORD}"
    result.fetch(:users).each do |role, user|
      puts "#{role}: #{user.email}"
    end
    puts "referral_code: #{result.fetch(:referral_code).code}"
    puts "store: #{result.fetch(:store).name}"
    puts "booth: #{result.fetch(:booth).name}"
  end
end

module ManualCapture
  class DataBuilder
    PASSWORD = "ManualCapture123!"
    REFERRAL_CODE = "MANUAL-CAPTURE-LOCAL"
    STORE_NAME = "マニュアル撮影用店舗"
    BOOTH_NAME = "マニュアル撮影用ブース"
    IVS_STAGE_ARN = "arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local"
    WALLET_POINTS = 100_000

    USERS = {
      system_admin: {
        email: "manual+system_admin@example.test",
        role: :system_admin,
        display_name: "マニュアル撮影用 運営",
        bio: "マニュアル撮影用の system_admin（運営）アカウントです。",
        phone_number: "+819000000001"
      },
      store_admin: {
        email: "manual+store_admin@example.test",
        role: :store_admin,
        display_name: "マニュアル撮影用 店舗管理者",
        bio: "マニュアル撮影用の store_admin（店舗管理者）アカウントです。",
        phone_number: "+819000000002"
      },
      cast: {
        email: "manual+cast@example.test",
        role: :cast,
        display_name: "マニュアル撮影用 キャスト",
        bio: "マニュアル撮影用の cast（配信者）アカウントです。",
        phone_number: "+819000000003"
      },
      customer: {
        email: "manual+customer@example.test",
        role: :customer,
        display_name: "マニュアル撮影用 視聴者",
        bio: "マニュアル撮影用の customer（視聴者）アカウントです。",
        phone_number: "+819000000004"
      }
    }.freeze

    def initialize(rails_env: Rails.env)
      @rails_env = rails_env
    end

    def call!
      raise "ManualCapture::DataBuilder is disabled in production" if @rails_env.production?

      result = {}

      ActiveRecord::Base.transaction do
        users = USERS.keys.index_with { |role| upsert_user!(role) }
        referral_code = upsert_referral_code!
        store = upsert_store!(referral_code)
        booth = upsert_booth!(store)

        upsert_store_membership!(store:, user: users.fetch(:store_admin), membership_role: :admin)
        upsert_store_membership!(store:, user: users.fetch(:cast), membership_role: :cast)
        upsert_booth_cast!(booth:, cast_user: users.fetch(:cast))
        upsert_default_drink_items!(store)
        upsert_wallet!(users.fetch(:customer))

        result = {
          users: users,
          referral_code: referral_code,
          store: store,
          booth: booth
        }
      end

      result
    end

    private

    def upsert_user!(role)
      attrs = USERS.fetch(role)
      user = User.find_or_initialize_by(email: attrs.fetch(:email))
      user.assign_attributes(
        role: attrs.fetch(:role),
        display_name: attrs.fetch(:display_name),
        bio: attrs.fetch(:bio),
        phone_number: attrs.fetch(:phone_number),
        phone_verified_at: occurred_at,
        deleted_at: nil,
        password: PASSWORD,
        password_confirmation: PASSWORD
      )
      user.save!
      user
    end

    def upsert_referral_code!
      referral_code = ReferralCode.find_or_initialize_by(code: REFERRAL_CODE)
      referral_code.update!(
        label: "マニュアル撮影用 紹介コード",
        enabled: true,
        expires_at: 1.year.from_now
      )
      referral_code
    end

    def upsert_store!(referral_code)
      store = Store.where(name: STORE_NAME).order(:id).first_or_initialize
      store.update!(
        referral_code: referral_code,
        name: STORE_NAME,
        description: "マニュアル撮影用の店舗です。通常データと区別できるように固定値で作成しています。",
        area: "マニュアル撮影用エリア",
        business_type: :girls_bar,
        phone_number: "03-0000-0000",
        business_hours: "20:00-25:00",
        onboarding_step: :skipped
      )
      store
    end

    def upsert_booth!(store)
      booth = Booth.where(store: store, name: BOOTH_NAME).order(:id).first_or_initialize
      booth.update!(
        name: BOOTH_NAME,
        description: "マニュアル撮影用のブースです。IVS Stage は疑似 ARN を設定しています。",
        status: :offline,
        archived_at: nil,
        current_stream_session: nil,
        ivs_stage_arn: IVS_STAGE_ARN,
        last_online_at: occurred_at
      )
      booth
    end

    def upsert_store_membership!(store:, user:, membership_role:)
      membership = StoreMembership.find_or_initialize_by(store: store, user: user)
      membership.update!(membership_role: membership_role)
      membership
    end

    def upsert_booth_cast!(booth:, cast_user:)
      booth_cast = BoothCast.where(booth: booth).order(:id).first_or_initialize
      booth_cast.update!(cast_user: cast_user)
      booth_cast
    end

    def upsert_default_drink_items!(store)
      default_drink_items_attributes.each do |attrs|
        drink_item = DrinkItem.find_or_initialize_by(store: store, position: attrs.fetch("position"))
        drink_item.update!(
          name: attrs.fetch("name"),
          price_points: attrs.fetch("price_points"),
          enabled: attrs.fetch("enabled"),
          icon_key: attrs["icon_key"]
        )
      end
    end

    def default_drink_items_attributes
      YAML.safe_load(
        Rails.root.join("config/default_drink_items.yml").read,
        aliases: true
      ).fetch(@rails_env.to_s).fetch("items")
    end

    def upsert_wallet!(customer_user)
      wallet = Wallet.find_or_initialize_by(customer_user: customer_user)
      wallet.update!(
        available_points: WALLET_POINTS,
        reserved_points: 0
      )

      transaction =
        WalletTransaction
          .where(wallet: wallet, kind: :adjustment, ref_type: nil, ref_id: nil, occurred_at: occurred_at)
          .first_or_initialize

      transaction.update!(
        points: WALLET_POINTS
      )

      wallet
    end

    def occurred_at
      Time.zone.local(2026, 1, 1, 0, 0, 0)
    end
  end
end
