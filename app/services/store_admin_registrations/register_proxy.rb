# frozen_string_literal: true

module StoreAdminRegistrations
  class RegisterProxy
    class NotAuthorized < StandardError; end
    class InvalidExistingRole < StandardError; end

    Result = Struct.new(
      :user,
      :membership,
      :status,
      :mail_delivered,
      :mail_error,
      keyword_init: true
    )

    def self.call!(store:, actor:, display_name:, email:)
      new(store:, actor:, display_name:, email:).call!
    end

    def initialize(store:, actor:, display_name:, email:)
      @store = store
      @actor = actor
      @display_name = display_name.to_s.strip
      @email = email.to_s.strip.downcase
    end

    def call!
      authorize_actor!
      result = provision_user_and_membership!
      deliver_instructions(result)
      result
    end

    private

    def authorize_actor!
      allowed =
        @actor&.store_registration_proxy_allowed? &&
        @store.present? &&
        @actor.admin_of_store?(@store.id)

      raise NotAuthorized unless allowed
    end

    def provision_user_and_membership!
      result = nil

      ActiveRecord::Base.transaction do
        user = User.active.lock.find_by(email: @email)

        if user.present?
          raise InvalidExistingRole unless user.store_admin?

          user.update!(display_name: @display_name) if user.display_name.blank?
          membership = StoreMembership.admin_only.find_by(store: @store, user: user)

          if membership.present?
            status = :already_member
          else
            membership = StoreMembership.create!(store: @store, user: user, membership_role: :admin)
            status = :added_to_store
          end
        else
          password = Devise.friendly_token(48)
          user = User.create!(
            email: @email,
            display_name: @display_name,
            password: password,
            password_confirmation: password,
            role: :store_admin
          )
          membership = StoreMembership.create!(store: @store, user: user, membership_role: :admin)
          status = :created
        end

        result = Result.new(user: user, membership: membership, status: status)
      end

      result
    end

    def deliver_instructions(result)
      reset_password_token = result.user.send(:set_reset_password_token)
      mailer = StoreAdminRegistrationMailer.with(
        user: result.user,
        store: @store,
        actor: @actor,
        reset_password_token: reset_password_token,
        registration_status: result.status
      )

      if result.status == :created
        mailer.new_user_instructions.deliver_now
      else
        mailer.existing_user_instructions.deliver_now
      end

      result.mail_delivered = true
    rescue StandardError => e
      result.mail_delivered = false
      result.mail_error = e
      Rails.logger.error("[store_admin_registration_proxy] mail delivery failed: #{e.class} #{e.message}")
    end
  end
end
