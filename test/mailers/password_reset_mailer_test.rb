# frozen_string_literal: true

require "test_helper"

class PasswordResetMailerTest < ActionMailer::TestCase
  test "reset password instructions show the 48 hour expiration" do
    user = User.create!(email: "password-mailer@example.com", password: "password", role: :customer)
    token = user.send(:set_reset_password_token)
    mail = Devise::Mailer.reset_password_instructions(user, token)

    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, "48時間"
      assert_not_includes body, "6時間"
    end
  end
end
