# frozen_string_literal: true

module StoreAdminInvitations
  class AcceptInvitation
    Result = Struct.new(:invitation, keyword_init: true)

    class NotUsable < StandardError; end
    class NotAuthorized < StandardError; end

    def self.call!(invitation:, actor:)
      new(invitation:, actor:).call!
    end

    def initialize(invitation:, actor:)
      @invitation = invitation
      @actor = actor
    end

    def call!
      raise NotAuthorized, "store_admin でログインしてください" unless @actor&.store_admin?

      ActiveRecord::Base.transaction do
        @invitation.lock!

        raise NotUsable, "この招待は使用できません（期限切れ/使用済み）" unless @invitation.usable?

        begin
          StoreMembership.create!(
            store: @invitation.store,
            user: @actor,
            membership_role: :admin
          )
        rescue ActiveRecord::RecordNotUnique
          # すでに所属済みでも、承認済みとして扱う（安全側・冪等）
        end

        @invitation.update!(
          used_at: Time.current,
          accepted_by_user: @actor
        )
      end

      Result.new(invitation: @invitation)
    end
  end
end
