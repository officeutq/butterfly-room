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

  DEFAULT_RANGE_DAYS = 30

  def initialize(store:, from: nil, to: nil, now: Time.zone.now)
    @store = store
    @now  = now

    @to   = (to || @now).to_time
    @from = (from || (@to - DEFAULT_RANGE_DAYS.days)).to_time
  end

  def call
    casts = store_cast_users

    sales_by_cast   = stream_sales_points_by_cast_user_id
    seconds_by_cast = stream_seconds_by_cast_user_id

    casts.map do |u|
      sales = sales_by_cast[u.id] || 0
      secs  = seconds_by_cast[u.id] || 0

      Row.new(
        cast_user: u,
        stream_sales_points: sales,
        stream_seconds: secs,
        sales_per_hour: calc_sales_per_hour(sales, secs),
        real_store_sales_yen: nil
      )
    end
  end

  private

  attr_reader :store, :from, :to, :now

  def store_cast_users
    User
      .joins(:store_memberships)
      .where(store_memberships: { store_id: store.id, membership_role: StoreMembership.membership_roles[:cast] })
      .distinct
      .order(:id)
  end

  def stream_sales_points_by_cast_user_id
    StoreLedgerEntry
      .joins(:stream_session)
      .where(store_id: store.id)
      .where(occurred_at: from...to)
      .group("stream_sessions.started_by_cast_user_id")
      .sum(:points)
  end

  def stream_seconds_by_cast_user_id
    sessions =
      StreamSession
        .where(store_id: store.id)
        .where("started_at < ? AND COALESCE(ended_at, ?) > ?", to, now, from)

    seconds_by_cast = Hash.new(0)

    sessions.find_each do |s|
      start_t = [ s.started_at, from ].max
      end_t   = [ s.ended_at || now, to ].min
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
end
