module CastInvitationsHelper
  def cast_invitation_share_text(invitation)
    name = invitation.invited_by_user.display_name.presence
    sender = name ? "#{name}様" : "管理者"
    "#{invitation.store.name}の#{sender}から、キャスト招待が届いています。\nURLをクリックして、バタフライブに参加しましょう！"
  end
end
