# frozen_string_literal: true

class SeoController < ApplicationController
  def sitemap
    render layout: false
  end
end
