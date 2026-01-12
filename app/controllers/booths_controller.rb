class BoothsController < ApplicationController
  def show
    @booth_id = params[:id]
  end
end
