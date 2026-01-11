module Admin
  class BaseController < ApplicationController
    before_action -> { require_role!(:store_admin, :system_admin) }
  end
end
