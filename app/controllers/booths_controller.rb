# frozen_string_literal: true

class BoothsController < ApplicationController
  def show
    @booth = Booth.find(params[:id])
    @stream_session = @booth.current_stream_session
  end
end
