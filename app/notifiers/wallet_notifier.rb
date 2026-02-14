# frozen_string_literal: true

class WalletNotifier
  def self.broadcast_balance_for_user(user)
    wallet = Wallet.find_by(customer_user_id: user.id)
    return if wallet.nil?

    Turbo::StreamsChannel.broadcast_replace_to(
      [ user, :wallet ],
      target: "wallet_balance",
      partial: "wallets/balance",
      locals: { wallet: wallet }
    )
  end

  def self.broadcast_balance_for_wallet_ids(wallet_ids)
    Array(wallet_ids).uniq.each do |wallet_id|
      wallet = Wallet.find_by(id: wallet_id)
      next if wallet.nil?

      user = wallet.customer_user
      next if user.nil?

      broadcast_balance_for_user(user)
    end
  end
end
