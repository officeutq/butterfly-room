# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260827010000_invalidate_expired_password_reset_tokens_before_extension")

class InvalidateExpiredPasswordResetTokensBeforeExtensionTest < ActiveSupport::TestCase
  test "invalidates only tokens already expired under the previous six hour limit" do
    travel_to Time.zone.local(2026, 8, 27, 12, 0, 0) do
      expired_user = create_user("expired-reset@example.com")
      active_user = create_user("active-reset@example.com")

      expired_token = expired_user.send(:set_reset_password_token)
      active_token = active_user.send(:set_reset_password_token)
      expired_user.update_columns(reset_password_sent_at: 7.hours.ago)
      active_user.update_columns(reset_password_sent_at: 5.hours.ago)

      InvalidateExpiredPasswordResetTokensBeforeExtension.new.up

      assert_nil expired_user.reload.reset_password_token
      assert_nil expired_user.reset_password_sent_at
      assert_nil User.with_reset_password_token(expired_token)

      assert active_user.reload.reset_password_token.present?
      assert active_user.reset_password_sent_at.present?
      assert_equal active_user, User.with_reset_password_token(active_token)
    end
  end

  private

  def create_user(email)
    User.create!(email:, password: "password", role: :store_admin)
  end
end
