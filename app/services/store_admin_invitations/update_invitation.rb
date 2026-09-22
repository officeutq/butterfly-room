# frozen_string_literal: true

module StoreAdminInvitations
  class UpdateInvitation
    class Conflict < StandardError; end
    class NotAuthorized < StandardError; end

    def self.call!(invitation:, actor:, action:, note: nil)
      invitation.with_lock do
        actor = User.active.find_by(id: actor&.id)
        unless actor && (actor.system_admin? || (actor.store_admin? && actor.admin_of_store?(invitation.store_id)))
          raise NotAuthorized, "この店舗の招待を変更する権限がありません"
        end

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
        else
          raise ArgumentError, "不明な操作です"
        end
      end
      invitation
    end
  end
end
