# frozen_string_literal: true

class SeoController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[sitemap]

  def sitemap
    render layout: false
  end
end
