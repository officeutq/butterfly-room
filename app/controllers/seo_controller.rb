# frozen_string_literal: true

class SeoController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[sitemap]

  def sitemap
    @stores = Store.published.order(:id)
    render layout: false
  end
end
