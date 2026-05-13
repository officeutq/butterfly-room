class LegalController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[
    show
    terms
    privacy_policy
    payment_services_act
  ]

  def show
  end

  def terms
  end

  def privacy_policy
  end

  def payment_services_act
  end
end
