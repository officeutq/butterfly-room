# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = User.where(deleted_at: nil).find(params[:id])
  end
end
