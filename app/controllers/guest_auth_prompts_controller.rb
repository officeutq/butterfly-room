# frozen_string_literal: true

class GuestAuthPromptsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    if user_signed_in?
      redirect_to root_path
      return
    end

    redirect_to welcome_path unless turbo_frame_request?
  end
end
