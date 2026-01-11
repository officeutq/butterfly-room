module Cast
  class BaseController < ApplicationController
    before_action -> { require_role!(:cast, :system_admin) }
  end
end
