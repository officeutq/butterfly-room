# frozen_string_literal: true

class CastMetricsQuery
  Row = Struct.new(
    :cast_user,
    :stream_sales_points,
    :stream_seconds,
    :sales_per_hour,
    :real_store_sales_yen,
    keyword_init: true
  )

  SHARE_RATE = BigDecimal("0.7")

  def initialize(store:, from:, to:, now: Time.zone.now, include_all_casts: false)
    @store = store
    @from = from.to_time
    @to = to.to_time
    @now = now
    @include_all_casts = include_all_casts
  end

  def call
    sales_by_cast = stream_sales_points_by_cast_user_id
    seconds_by_cast = stream_seconds_by_cast_user_id

    casts =
      store_cast_users.select do |u|
        include_all_casts || sales_by_cast[u.id].to_i.positive? || seconds_by_cast[u.id].to_i.positive?
      end

    casts
      .map do |u|
        sales = sales_by_cast[u.id] || 0
        secs = seconds_by_cast[u.id] || 0

        Row.new(
          cast_user: u,
          stream_sales_points: sales,
          stream_seconds: secs,
          sales_per_hour: calc_sales_per_hour(sales, secs),
          real_store_sales_yen: calc_store_share_yen(sales)
        )
      end
      .sort_by { |r| [ -r.stream_sales_points.to_i, -r.stream_seconds.to_i, r.cast_user.id ] }
  end

  private

  attr_reader :store, :from, :to, :now, :include_all_casts

  def store_cast_users
    BoothCast
      .joins(:booth)
      .includes(:cast_user)
      .where(booths: { store_id: store.id })
      .map(&:cast_user)
      .uniq
      .sort_by(&:id)
  end

  def stream_sales_points_by_cast_user_id
    StoreLedgerEntry
      .joins(:stream_session)
      .where(store_id: store.id)
      .where(occurred_at: from...to)
      .group("stream_sessions.started_by_cast_user_id")
      .sum(:points)
      .compact
  end

  def stream_seconds_by_cast_user_id
    sessions =
      StreamSession
        .where(store_id: store.id)
        .where.not(broadcast_started_at: nil)
        .where("broadcast_started_at < ? AND COALESCE(ended_at, ?) > ?", to, now, from)

    seconds_by_cast = Hash.new(0)

    sessions.find_each do |s|
      next if s.started_by_cast_user_id.blank?

      start_t = [ s.broadcast_started_at, from ].max
      end_t = [ s.ended_at || now, to ].min

      dur = end_t - start_t
      dur = 0 if dur.negative?

      seconds_by_cast[s.started_by_cast_user_id] += dur.to_i
    end

    seconds_by_cast
  end

  def calc_sales_per_hour(points, seconds)
    return nil if seconds.to_i <= 0

    (points.to_f / (seconds.to_f / 3600.0)).round(2)
  end

  def calc_store_share_yen(points)
    (BigDecimal(points.to_i) * SHARE_RATE).floor(0).to_i
  end
end
