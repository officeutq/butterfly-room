class BoothsController < ApplicationController
  def show
    # booth = Booth.find(params[:id])   # 後で
    # authorize!(Authorization::BoothPolicy, booth, :show)
    render plain: "booth show (stub)"
  end
end
