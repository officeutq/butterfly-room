class LegalController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[
    show
    terms
    privacy_policy
  ]

  def show
  end

  def terms
  end

  def privacy_policy
  end
end
