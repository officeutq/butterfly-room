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
    puts "secondary_store: #{result.fetch(:secondary_store).name}"
    puts "booth: #{result.fetch(:booth).name}"
    puts "secondary_booth: #{result.fetch(:secondary_booth).name}"
  end

  desc "Prepare development/test-only live customer viewer data for user manual screenshots"
  task prepare_customer_viewer: :environment do
    if Rails.env.production?
      raise "manual_capture:prepare_customer_viewer is disabled in production"
    end

    result = ManualCapture::CustomerViewerDataBuilder.new.call!

    puts "manual capture customer viewer data prepared"
    puts "customer: #{result.fetch(:customer).email}"
    puts "store: #{result.fetch(:store).name}"
    puts "offline_booth: #{result.fetch(:offline_booth).name}"
    puts "live_booth: #{result.fetch(:live_booth).name}"
    puts "stream_session: #{result.fetch(:stream_session).id}"
  end
end

module ManualCapture
  class DataBuilder
    PASSWORD = "ManualCapture123!"
    REFERRAL_CODE = "MANUAL-CAPTURE-LOCAL"
    STORE_NAME = "マニュアル撮影用店舗"
    SECONDARY_STORE_NAME = "マニュアル撮影用サブ店舗"
    BOOTH_NAME = "マニュアル撮影用ブース"
    SECONDARY_BOOTH_NAME = "マニュアル撮影用サブブース"
    IVS_STAGE_ARN = "arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local"
    SECONDARY_IVS_STAGE_ARN = "arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local-secondary"
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
        secondary_store = upsert_secondary_store!(referral_code)
        booth = upsert_booth!(store)
        secondary_booth = upsert_secondary_booth!(store)

        upsert_store_membership!(store:, user: users.fetch(:store_admin), membership_role: :admin)
        upsert_store_membership!(store: secondary_store, user: users.fetch(:store_admin), membership_role: :admin)
        upsert_store_membership!(store:, user: users.fetch(:cast), membership_role: :cast)
        upsert_booth_cast!(booth:, cast_user: users.fetch(:cast))
        upsert_booth_cast!(booth: secondary_booth, cast_user: users.fetch(:cast))
        archive_extra_manual_cast_booths!(
          cast_user: users.fetch(:cast),
          keep_booths: [ booth, secondary_booth ]
        )
        upsert_default_drink_items!(store)
        upsert_wallet!(users.fetch(:customer))

        result = {
          users: users,
          referral_code: referral_code,
          store: store,
          secondary_store: secondary_store,
          booth: booth,
          secondary_booth: secondary_booth
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

    def upsert_secondary_store!(referral_code)
      store = Store.where(name: SECONDARY_STORE_NAME).order(:id).first_or_initialize
      store.update!(
        referral_code: referral_code,
        name: SECONDARY_STORE_NAME,
        description: "マニュアル撮影用の店舗選択画面に表示するサブ店舗です。",
        area: "マニュアル撮影用エリア",
        business_type: :girls_bar,
        phone_number: "03-0000-0001",
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

    def upsert_secondary_booth!(store)
      booth = Booth.where(store: store, name: SECONDARY_BOOTH_NAME).order(:id).first_or_initialize
      booth.update!(
        name: SECONDARY_BOOTH_NAME,
        description: "マニュアル撮影用のブース一覧・切り替え確認用サブブースです。IVS Stage は疑似 ARN を設定しています。",
        status: :offline,
        archived_at: nil,
        current_stream_session: nil,
        ivs_stage_arn: SECONDARY_IVS_STAGE_ARN,
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

    def archive_extra_manual_cast_booths!(cast_user:, keep_booths:)
      keep_ids = keep_booths.map(&:id)

      Booth
        .joins(:booth_casts)
        .where(booth_casts: { cast_user_id: cast_user.id })
        .where(archived_at: nil)
        .where.not(id: keep_ids)
        .where("booths.name LIKE ?", "マニュアル撮影用%")
        .find_each do |booth|
          booth.update!(
            status: :offline,
            current_stream_session: nil,
            archived_at: occurred_at
          )
        end
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

  class CustomerViewerDataBuilder
    STREAM_TITLE = "マニュアル撮影用ライブ配信"
    COMMENT_BODY = "マニュアル撮影用のコメントです。".freeze

    def initialize(rails_env: Rails.env)
      @rails_env = rails_env
    end

    def call!
      raise "ManualCapture::CustomerViewerDataBuilder is disabled in production" if @rails_env.production?

      base = DataBuilder.new(rails_env: @rails_env).call!
      users = base.fetch(:users)
      store = base.fetch(:store)
      offline_booth = base.fetch(:booth)
      live_booth = base.fetch(:secondary_booth)
      cast_user = users.fetch(:cast)
      customer = users.fetch(:customer)

      stream_session = nil

      ActiveRecord::Base.transaction do
        stream_session = upsert_live_stream_session!(
          booth: live_booth,
          store: store,
          cast_user: cast_user
        )

        upsert_manual_comment!(
          stream_session: stream_session,
          booth: live_booth,
          customer: customer
        )

        upsert_favorites!(
          customer: customer,
          booth: live_booth,
          store: store,
          cast_user: cast_user
        )
      end

      {
        customer: customer,
        store: store,
        offline_booth: offline_booth,
        live_booth: live_booth.reload,
        stream_session: stream_session
      }
    end

    private

    def upsert_live_stream_session!(booth:, store:, cast_user:)
      stream_session =
        StreamSession
          .where(booth: booth, started_by_cast_user: cast_user, title: STREAM_TITLE)
          .order(:id)
          .first_or_initialize

      stream_session.update!(
        store: store,
        status: :live,
        started_at: live_started_at,
        broadcast_started_at: live_started_at,
        ended_at: nil,
        ivs_stage_arn: booth.ivs_stage_arn
      )

      booth.update!(
        status: :live,
        current_stream_session: stream_session,
        last_online_at: live_started_at
      )

      stream_session
    end

    def live_started_at
      Time.zone.local(2026, 1, 1, 12, 0, 0)
    end

    def upsert_manual_comment!(stream_session:, booth:, customer:)
      comment =
        Comment
          .where(
            stream_session: stream_session,
            booth: booth,
            user: customer,
            kind: Comment::KIND_CHAT,
            body: COMMENT_BODY
          )
          .order(:id)
          .first_or_initialize

      comment.update!(
        metadata: {},
        deleted_at: nil
      )

      comment
    end

    def upsert_favorites!(customer:, booth:, store:, cast_user:)
      FavoriteBooth.find_or_create_by!(user: customer, booth: booth)
      FavoriteStore.find_or_create_by!(user: customer, store: store)
      FavoriteUser.find_or_create_by!(user: customer, target_user: cast_user)
    end
  end
end
