# frozen_string_literal: true

module StoreCastInvitations
  class AcceptInvitation
    Result = Struct.new(:invitation, :booth, keyword_init: true)

    class NotUsable < StandardError; end
    class NotAuthorized < StandardError; end
    class Broadcasting < NotAuthorized; end
    class BroadcastUnavailable < NotAuthorized; end

    def self.call!(invitation:, actor:)
      new(invitation:, actor:).call!
    end

    def self.consume_if_already_member!(invitation:, actor:)
      new(invitation:, actor:).consume_if_already_member!
    end

    def initialize(invitation:, actor:)
      @invitation = invitation
      @actor = actor
    end

    def call!
      booth = nil

      with_actor_lock do
        raise NotUsable, "この招待は使用できません（取消済み/期限切れ/使用済み）" unless @invitation.usable?
        raise NotUsable, "この店舗にはすでにキャストとして登録されています" if already_member?

        StoreMembership.create!(
          store: @invitation.store,
          user: @actor,
          membership_role: :cast
        )

        booth = Booth.create!(
          store: @invitation.store,
          name: booth_name_for(@actor)
        )

        Booths::ProvisionIvsStageService.new(booth: booth).call!

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

    def consume_if_already_member!
      with_actor_lock do
        member = already_member?
        if member && @invitation.usable?
          @invitation.update!(used_at: Time.current, accepted_by_user: @actor)
        end
        member
      end
    end

    private

    def with_actor_lock
      User.transaction do
        # 配信成功確定・退会と同じ人物を先にロックする。参照側の外部キーとは競合させない。
        @actor = User.active.lock("FOR NO KEY UPDATE").find_by(id: @actor&.id)
        raise NotAuthorized, "cast でログインしてください" unless @actor&.cast?

        check_broadcast!
        @invitation.lock!
        yield
      end
    end

    def check_broadcast!
      if StreamSession.current_broadcast_for_selection(@actor)
        raise Broadcasting, "配信を終了してから招待を承認してください"
      end
    rescue StreamSession::CurrentBroadcastInconsistent
      raise BroadcastUnavailable, "配信状態を確認できません。時間をおいて再度確認してください"
    end

    def already_member?
      StoreMembership.exists?(store_id: @invitation.store_id, user_id: @actor.id, membership_role: :cast)
    end

    def booth_name_for(user)
      "#{ApplicationController.helpers.display_name_or_anonymous(user)}のブース"
    end
  end
end
