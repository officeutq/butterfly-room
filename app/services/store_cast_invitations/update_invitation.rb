# frozen_string_literal: true

module StoreCastInvitations
  class UpdateInvitation
    class Conflict < StandardError; end

    def self.call!(invitation:, action:, note: nil)
      invitation.with_lock do
        case action
        when :note
          raise Conflict, "取消済みの招待は変更できません" if invitation.cancelled?
          invitation.update!(note: note.presence)
        when :cancel
          raise Conflict, "共有済み・使用済みの招待は取り消せません" if invitation.used? || invitation.shared_at.present?
          invitation.update!(cancelled_at: Time.current) unless invitation.cancelled?
        when :shared
          raise Conflict, "この招待は使用できません" if invitation.cancelled? || invitation.expired?
          invitation.update!(shared_at: Time.current) unless invitation.shared_at.present?
          invitation.store.with_lock { invitation.store.mark_onboarding_invite_copied! }
        else
          raise ArgumentError, "不明な操作です"
        end
      end
      invitation
    end
  end
end
