# frozen_string_literal: true

module SystemAdmin
  class BaseController < ApplicationController
    before_action -> { require_role!(:system_admin) }
  end
end
