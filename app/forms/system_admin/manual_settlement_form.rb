# frozen_string_literal: true

module SystemAdmin
  class ManualSettlementForm
    include ActiveModel::Model
    include ActiveModel::Attributes

    ZONE = "Asia/Tokyo"

    attribute :store_id, :integer
    attribute :period_from, :datetime
    attribute :period_to, :datetime

    validates :store_id, presence: true
    validates :period_from, presence: true
    validates :period_to, presence: true
    validate :period_range_validation
    validate :overlap_validation

    def period_from=(value)
      super(parse_time(value))
    end

    def period_to=(value)
      super(parse_time(value))
    end

    private

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil if value.blank?

      Time.use_zone(ZONE) { Time.zone.parse(value.to_s) }
    end

    def period_range_validation
      return if period_from.blank? || period_to.blank?

      errors.add(:period_to, "は period_from より後にしてください") unless period_from < period_to
    end

    def overlap_validation
      return if store_id.blank? || period_from.blank? || period_to.blank?

      existing =
        Settlement
          .where(store_id: store_id)
          .where("tsrange(period_from, period_to) && tsrange(?, ?)", period_from, period_to)
          .order(period_from: :asc)
          .first

      return if existing.blank?

      from_str = existing.period_from.in_time_zone(ZONE).strftime("%Y-%m-%d %H:%M")
      to_str   = existing.period_to.in_time_zone(ZONE).strftime("%Y-%m-%d %H:%M")
      errors.add(:base, "この期間は既に精算済みです（#{from_str}..#{to_str}）")
    end
  end
end
