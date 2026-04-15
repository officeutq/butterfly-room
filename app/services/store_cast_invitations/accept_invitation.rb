# frozen_string_literal: true

module StoreCastInvitations
  class AcceptInvitation
    Result = Struct.new(:invitation, :booth, keyword_init: true)

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
      raise NotAuthorized, "cast でログインしてください" unless @actor&.cast?

      booth = nil

      ActiveRecord::Base.transaction do
        @invitation.lock!

        raise NotUsable, "この招待は使用できません（期限切れ/使用済み）" unless @invitation.usable?

        begin
          StoreMembership.create!(
            store: @invitation.store,
            user: @actor,
            membership_role: :cast
          )
        rescue ActiveRecord::RecordNotUnique
          # すでに所属済みでも、承認済みとして扱う（安全側・冪等）
        end

        booth = Booth.create!(
          store: @invitation.store,
          name: booth_name_for(@actor)
        )

        BoothCast.create!(
          booth: booth,
          cast_user: @actor
        )

        @invitation.update!(
          used_at: Time.current,
          accepted_by_user: @actor
        )
      end

      Result.new(invitation: @invitation, booth: booth)
    end

    private

    def booth_name_for(user)
      "#{ApplicationController.helpers.display_name_or_anonymous(user)}のブース"
    end
  end
end
