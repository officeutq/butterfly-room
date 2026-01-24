# frozen_string_literal: true

module Wallets
  class ReleaseService
    class InsufficientReserved < StandardError; end

    def initialize(wallet:, points:)
      @wallet = wallet
      @points = points.to_i
    end

    def call!
      raise ArgumentError, "points must be positive" unless @points.positive?

      wallet = Wallet.lock.find(@wallet.id)

      if wallet.reserved_points < @points
        raise InsufficientReserved, "reserved_points不足 (reserved=#{wallet.reserved_points}, release=#{@points})"
      end

      wallet.update!(
        reserved_points:  wallet.reserved_points - @points,
        available_points: wallet.available_points + @points
      )

      wallet
    end
  end
end
