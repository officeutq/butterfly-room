# frozen_string_literal: true

require "test_helper"

class StagingDirectMailDeliveryTest < ActionMailer::TestCase
  test "password reset delivery keeps each account recipient and token" do
    with_direct_delivery do
      2.times do |index|
        user = User.create!(email: "direct-reset-#{index}@example.com", password: "password", role: :customer)
        token = nil

        assert_emails 1 do
          token = user.send_reset_password_instructions
        end

        mail = ActionMailer::Base.deliveries.last
        assert_equal [ user.email ], mail.to
        assert_equal user.id, User.with_reset_password_token(token).id
        [ mail.text_part, mail.html_part ].each do |part|
          assert_includes part.body.decoded, user.email
          assert_includes part.body.decoded, "reset_password_token=#{token}"
        end
      end
    end
  end

  test "new and existing store admin instructions keep each intended recipient" do
    store = Store.create!(name: "Direct mail store")
    actor = User.create!(email: "direct-actor@example.com", password: "password", role: :store_admin)

    with_direct_delivery do
      { new_user_instructions: :created, existing_user_instructions: :added_to_store }.each do |action, status|
        user = User.create!(email: "direct-#{status}@example.com", password: "password", role: :store_admin)
        token = user.send(:set_reset_password_token)

        assert_emails 1 do
          StoreAdminRegistrationMailer.with(
            user: user, store: store, actor: actor,
            reset_password_token: token, registration_status: status
          ).public_send(action).deliver_now
        end

        mail = ActionMailer::Base.deliveries.last
        assert_equal [ user.email ], mail.to
        [ mail.text_part, mail.html_part ].each do |part|
          assert_includes part.body.decoded, "reset_password_token=#{token}"
        end
      end
    end
  end

  private

  def with_direct_delivery(&block)
    with_env({
      "APP_ENV" => "staging",
      "MAIL_DELIVERY_ENABLED" => "true",
      "MAIL_DELIVERY_MODE" => "direct",
      "MAIL_REDIRECT_RECIPIENT" => "redirect@example.com",
      "MAIL_ALLOWED_RECIPIENTS" => "allowed@example.com",
      "MAIL_SUBJECT_PREFIX" => "[STAGING]"
    }, &block)
  end
end
