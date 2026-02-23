class CheckoutController < ApplicationController
  before_action :authenticate_user!

  def return
    @status = params[:status].to_s
    @return_to = safe_return_path(params[:return_to])

    @wallet = Wallet.find_by(customer_user_id: current_user.id)

    render :return
  end

  private

  def safe_return_path(path)
    return nil if path.blank?
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//")

    path
  end
end
