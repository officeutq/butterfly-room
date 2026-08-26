# frozen_string_literal: true

class InvalidateExpiredPasswordResetTokensBeforeExtension < ActiveRecord::Migration[8.1]
  PREVIOUS_RESET_PASSWORD_WITHIN = 6.hours

  def up
    cutoff = connection.quote(Time.current - PREVIOUS_RESET_PASSWORD_WITHIN)

    execute <<~SQL.squish
      UPDATE users
      SET reset_password_token = NULL,
          reset_password_sent_at = NULL,
          updated_at = CURRENT_TIMESTAMP
      WHERE reset_password_token IS NOT NULL
        AND (reset_password_sent_at IS NULL OR reset_password_sent_at < #{cutoff})
    SQL
  end

  def down
    # 無効化したトークンは復元できない。
  end
end
