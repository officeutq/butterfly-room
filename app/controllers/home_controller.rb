# frozen_string_literal: true

class HomeController < ApplicationController
  def show
    @mode = params[:mode].to_s
    @mode = "booths" unless %w[booths stores].include?(@mode)

    @q = params[:q].to_s.strip
    q_like =
      if @q.present?
        escaped = ActiveRecord::Base.sanitize_sql_like(@q)
        "%#{escaped}%"
      end

    if @mode == "stores"
      @booths = Booth.none

      stores =
        Store
          .where(id: Booth.active.select(:store_id)) # active booth を持つ store だけ（現状踏襲）

      # store name で絞り込み
      stores = stores.where("stores.name ILIKE ?", q_like) if q_like.present?

      # 店舗ごとの latest_online_started_at（live/away を online 扱い）
      online_latest =
        Booth.active
             .where(status: %i[live away])
             .joins("INNER JOIN stream_sessions current_ss ON current_ss.id = booths.current_stream_session_id")
             .select("booths.store_id AS store_id, MAX(current_ss.started_at) AS latest_online_started_at")
             .group("booths.store_id")

      stores =
        stores
          .joins("LEFT JOIN (#{online_latest.to_sql}) online_latest ON online_latest.store_id = stores.id")
          .order(Arel.sql("online_latest.latest_online_started_at DESC NULLS LAST"), id: :desc)
          .limit(30)

      # customer はBAN店舗を除外（現状踏襲）
      if user_signed_in? && current_user.customer?
        banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
        stores = stores.where.not(id: banned_store_ids)
      end

      @stores = stores

      # favorites（表示対象だけ）
      if user_signed_in?
        @favorite_store_ids =
          current_user.favorite_stores.where(store_id: @stores.select(:id)).pluck(:store_id).to_set
      else
        @favorite_store_ids = Set.new
      end
      @favorite_booth_ids = Set.new

      return
    end

    # --- mode=booths ---
    @stores = Store.none

    booths = Booth.active

    # current_stream_session.started_at を order で使うため JOIN
    booths =
      booths.joins(<<~SQL)
        LEFT JOIN stream_sessions current_ss
          ON current_ss.id = booths.current_stream_session_id
      SQL

    # booth name で絞り込み（仕様どおり stores.name は対象外）
    booths = booths.where("booths.name ILIKE ?", q_like) if q_like.present?

    # online（live/away）優先
    online_order =
      "CASE WHEN booths.status IN (#{Booth.statuses[:live]}, #{Booth.statuses[:away]}) THEN 1 ELSE 0 END"

    booths =
      booths
        .includes(
          :store,
          { booth_casts: :cast_user },
          thumbnail_image_attachment: :blob
        )
        .order(
          Arel.sql("#{online_order} DESC"),
          Arel.sql("current_ss.started_at DESC NULLS LAST"),
          id: :desc
        )
        .limit(60)

    # customer はBAN店舗を除外（現状踏襲）
    if user_signed_in? && current_user.customer?
      banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
      booths = booths.where.not(store_id: banned_store_ids)
    end

    @booths = booths

    # favorites（表示対象だけ）
    if user_signed_in?
      @favorite_booth_ids =
        current_user.favorite_booths.where(booth_id: @booths.select(:id)).pluck(:booth_id).to_set
    else
      @favorite_booth_ids = Set.new
    end
    @favorite_store_ids = Set.new
  end
end
