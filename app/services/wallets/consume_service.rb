# frozen_string_literal: true

module Wallets
  class ConsumeService
    class InsufficientReservedPoints < StandardError; end

    def initialize(wallet:, points:, ref: nil, occurred_at: Time.current)
      @wallet = wallet
      @points = points.to_i
      @ref = ref
      @occurred_at = occurred_at
    end

    def call!
      raise ArgumentError, "points must be positive" unless @points.positive?

      @wallet.with_lock do
        if @wallet.reserved_points < @points
          raise InsufficientReservedPoints
        end

        @wallet.reserved_points -= @points
        @wallet.save!

        WalletTransaction.create!(
          wallet: @wallet,
          kind: :consume,
          points: @points,
          ref: @ref,
          occurred_at: @occurred_at
        )
      end

      @wallet
    end
  end
end
