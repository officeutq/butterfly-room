# frozen_string_literal: true

module LpAnalytics
  class DimensionOptionsQuery
    Result = Data.define(:lp_identifiers, :traffic_sources, :device_types)

    def call
      Result.new(
        lp_identifiers: Configuration::LP_DEFINITIONS.keys,
        traffic_sources: Visit.where.not(traffic_source: [ nil, "" ]).distinct.order(:traffic_source).pluck(:traffic_source),
        device_types: Visit::DEVICE_TYPES
      )
    end
  end
end
