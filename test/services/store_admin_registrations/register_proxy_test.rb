# frozen_string_literal: true

require "test_helper"

module StoreAdminRegistrations
  class RegisterProxyTest < ActiveSupport::TestCase
    setup do
      ActionMailer::Base.deliveries.clear
      @store = Store.create!(name: "Registration Target")
      @actor = User.create!(
        email: "registration-actor@example.com",
        password: "password",
        role: :store_admin,
        display_name: "Registration Agent"
      )
      StoreMembership.create!(store: @store, user: @actor, membership_role: :admin)
      @support_company = Store.create!(name: "Support Company", sales_support_company: true)
      StoreMembership.create!(store: @support_company, user: @actor, membership_role: :admin)
    end

    test "creates a new store_admin and membership then sends password setup instructions" do
      result = nil

      assert_difference "User.count", 1 do
        assert_difference "StoreMembership.count", 1 do
          assert_difference "ActionMailer::Base.deliveries.size", 1 do
            result = RegisterProxy.call!(
              store: @store,
              actor: @actor,
              display_name: "Responsible Person",
              email: "new-responsible@example.com"
            )
          end
        end
      end

      assert_equal :created, result.status
      assert result.mail_delivered
      assert result.user.store_admin?
      assert_equal "Responsible Person", result.user.display_name
      assert result.user.reset_password_token.present?
      assert StoreMembership.admin_only.exists?(store: @store, user: result.user)

      body = ActionMailer::Base.deliveries.last.text_part.body.decoded
      assert_includes body, "パスワード設定URL"
      assert_includes body, result.user.email
      assert_includes body, "Registration Agentによって"
      assert_not_includes body, "仮パスワード:"
    end

    test "adds an existing store_admin without overwriting an existing display name" do
      user = User.create!(
        email: "existing-responsible@example.com",
        password: "password",
        role: :store_admin,
        display_name: "Existing Name"
      )

      assert_no_difference "User.count" do
        assert_difference "StoreMembership.count", 1 do
          @result = RegisterProxy.call!(
            store: @store,
            actor: @actor,
            display_name: "Replacement Name",
            email: user.email
          )
        end
      end

      assert_equal :added_to_store, @result.status
      assert_equal "Existing Name", user.reload.display_name
      assert @result.mail_delivered
    end

    test "fills a blank display name and resends without duplicating membership" do
      user = User.create!(email: "blank-name@example.com", password: "password", role: :store_admin)
      StoreMembership.create!(store: @store, user: user, membership_role: :admin)

      assert_no_difference [ "User.count", "StoreMembership.count" ] do
        @result = RegisterProxy.call!(
          store: @store,
          actor: @actor,
          display_name: "Filled Name",
          email: user.email
        )
      end

      assert_equal :already_member, @result.status
      assert_equal "Filled Name", user.reload.display_name
      assert @result.mail_delivered
    end

    test "an active non store_admin is rejected without side effects" do
      customer = User.create!(email: "wrong-role@example.com", password: "password", role: :customer)

      assert_no_difference [ "User.count", "StoreMembership.count", "ActionMailer::Base.deliveries.size" ] do
        assert_raises RegisterProxy::InvalidExistingRole do
          RegisterProxy.call!(
            store: @store,
            actor: @actor,
            display_name: "Wrong Role",
            email: customer.email
          )
        end
      end
    end

    test "a retired email creates a new store_admin account" do
      stopped = User.create!(
        email: "stopped-admin@example.com",
        password: "password",
        role: :store_admin,
        deleted_at: Time.current
      )

      result = nil
      assert_difference "User.count", 1 do
        assert_difference "StoreMembership.count", 1 do
          result = RegisterProxy.call!(
            store: @store,
            actor: @actor,
            display_name: "New Account",
            email: stopped.email
          )
        end
      end

      assert_equal :created, result.status
      assert_not_equal stopped.id, result.user.id
      assert result.user.active_for_authentication?
    end

    test "mail failure keeps data and a repeated call can resend instructions" do
      failing_mailer = Object.new
      def failing_mailer.new_user_instructions = self
      def failing_mailer.existing_user_instructions = self
      def failing_mailer.deliver_now = raise("delivery failed")

      result = nil
      original_method = StoreAdminRegistrationMailer.method(:with)
      StoreAdminRegistrationMailer.define_singleton_method(:with) { |*args, **kwargs| failing_mailer }

      begin
        result = RegisterProxy.call!(
          store: @store,
          actor: @actor,
          display_name: "Retry Person",
          email: "retry-responsible@example.com"
        )
      ensure
        StoreAdminRegistrationMailer.define_singleton_method(:with, original_method)
      end

      assert_equal :created, result.status
      assert_not result.mail_delivered
      assert result.user.persisted?
      assert result.membership.persisted?

      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        retry_result = RegisterProxy.call!(
          store: @store,
          actor: @actor,
          display_name: "Retry Person",
          email: result.user.email
        )
        assert_equal :already_member, retry_result.status
        assert retry_result.mail_delivered
      end
    end

    test "actor without proxy permission or target store admin membership is rejected" do
      @support_company.update!(sales_support_company: false)

      assert_raises RegisterProxy::NotAuthorized do
        RegisterProxy.call!(
          store: @store,
          actor: @actor,
          display_name: "Denied",
          email: "denied-without-proxy@example.com"
        )
      end

      @support_company.update!(sales_support_company: true)
      other_store = Store.create!(name: "Other Store")

      assert_raises RegisterProxy::NotAuthorized do
        RegisterProxy.call!(
          store: other_store,
          actor: @actor,
          display_name: "Denied",
          email: "denied-without-membership@example.com"
        )
      end
    end

    test "stopped actor is rejected" do
      @actor.update!(deleted_at: Time.current)

      assert_raises RegisterProxy::NotAuthorized do
        RegisterProxy.call!(
          store: @store,
          actor: @actor,
          display_name: "Denied",
          email: "denied-stopped-actor@example.com"
        )
      end
    end
  end
end
