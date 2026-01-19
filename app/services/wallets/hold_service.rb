# frozen_string_literal: true

module Wallets
  class HoldService
    class InsufficientPoints < StandardError; end

    def initialize(wallet:, points:)
      @wallet = wallet
      @points = points.to_i
    end

    def call!
      raise ArgumentError, "points must be positive" unless @points.positive?

      @wallet.with_lock do
        if @wallet.available_points < @points
          raise InsufficientPoints
        end

        @wallet.available_points -= @points
        @wallet.reserved_points  += @points
        @wallet.save!
      end

      @wallet
    end
  end
end
