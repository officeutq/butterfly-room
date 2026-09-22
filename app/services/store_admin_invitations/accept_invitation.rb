# frozen_string_literal: true

module StoreAdminInvitations
  class AcceptInvitation
    Result = Struct.new(:invitation, keyword_init: true)

    class NotUsable < StandardError; end
    class NotAuthorized < StandardError; end

    def self.call!(invitation:, actor:)
      new(invitation:, actor:).call!
    end

    def self.accept_if_member!(invitation:, actor:)
      new(invitation:, actor:).call!(existing_member_only: true)
    end

    def initialize(invitation:, actor:)
      @invitation = invitation
      @actor = actor
    end

    def call!(existing_member_only: false)
      raise NotAuthorized, "store_admin でログインしてください" unless @actor&.store_admin? && !@actor.deleted?

      ActiveRecord::Base.transaction do
        @invitation.lock!

        if existing_member_only
          return unless @invitation.usable? && StoreMembership.admin_only.exists?(store: @invitation.store, user: @actor)
        end
        raise NotUsable, "この招待は使用できません（取消済み/期限切れ/使用済み）" unless @invitation.usable?

        StoreMembership.create_or_find_by!(
          store: @invitation.store,
          user: @actor,
          membership_role: :admin
        )

        @invitation.update!(
          used_at: Time.current,
          accepted_by_user: @actor
        )
      end

      Result.new(invitation: @invitation)
    end
  end
end
