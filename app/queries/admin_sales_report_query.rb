# frozen_string_literal: true

class AdminSalesReportQuery
  ZONE = "Asia/Tokyo"

  Result = Data.define(:store, :period_from, :period_to, :month_total_points, :daily_rows, :booth_rows)
  DailyRow = Data.define(:date, :points)
  BoothRow = Data.define(:booth_id, :booth_name, :points)

  def initialize(store:, from:, to:, zone: ZONE)
    @store = store
    @zone = zone
    @from = from.in_time_zone(zone)
    @to = to.in_time_zone(zone)
  end

  def call
    relation = ledger_entries

    Result.new(
      store: store,
      period_from: from,
      period_to: to,
      month_total_points: relation.sum(:points).to_i,
      daily_rows: daily_rows(relation),
      booth_rows: booth_rows(relation)
    )
  end

  private

  attr_reader :store, :from, :to, :zone

  def ledger_entries
    StoreLedgerEntry.where(store_id: store.id, occurred_at: from...to)
  end

  def daily_rows(relation)
    points_by_date = Hash.new(0)

    relation.select(:id, :occurred_at, :points).find_each do |entry|
      date = entry.occurred_at.in_time_zone(zone).to_date
      points_by_date[date] += entry.points.to_i
    end

    (from.to_date...to.to_date).map do |date|
      DailyRow.new(date: date, points: points_by_date[date].to_i)
    end
  end

  def booth_rows(relation)
    relation
      .joins(stream_session: :booth)
      .group("booths.id", "booths.name")
      .pluck("booths.id", "booths.name", Arel.sql("SUM(store_ledger_entries.points)"))
      .map { |booth_id, booth_name, points| BoothRow.new(booth_id:, booth_name:, points: points.to_i) }
      .sort_by { |row| [ -row.points, row.booth_id ] }
  end
end
