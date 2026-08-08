# frozen_string_literal: true

require "test_helper"

class SystemAdminRemovedRoutesTest < ActionDispatch::IntegrationTest
  test "additional user permission management route no longer exists" do
    assert_raises ActionController::RoutingError do
      Rails.application.routes.recognize_path("/system_admin/user_permissions", method: :get)
    end
  end
end
