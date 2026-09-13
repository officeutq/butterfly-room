# frozen_string_literal: true

module CommentsHelper
  def comment_member_profile_ids(comments)
    User.member_profiles.where(id: comments.map(&:user_id)).pluck(:id).to_set
  end

  def comment_author_link(user, guest_viewer:, member_profile_ids: nil)
    name = display_name_or_anonymous(user)
    return name if guest_viewer || user.deleted?

    visible_to_members = if member_profile_ids
      member_profile_ids.include?(user.id)
    else
      User.member_profiles.exists?(id: user.id)
    end

    if visible_to_members
      link_to name, user_path(user), class: "text-decoration-none text-reset"
    else
      # 共有配信に本人用リンクを含めず、各ブラウザーで本人だけ補う。
      content_tag :span, name, data: {
        controller: "self-profile-link",
        self_profile_link_user_id_value: user.id.to_s,
        self_profile_link_url_value: user_path(user),
        action: "turbo:before-cache@document->self-profile-link#reset"
      }
    end
  end
end
