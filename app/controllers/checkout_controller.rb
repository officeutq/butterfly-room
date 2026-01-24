class CheckoutController < ApplicationController
  before_action :authenticate_user!

  def return
    @status = params[:status].to_s
    @booth_id = params[:booth_id]

    @wallet = Wallet.find_by(customer_user_id: current_user.id)

    render :return
  end
end
