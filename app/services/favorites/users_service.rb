# frozen_string_literal: true

module Favorites
  class UsersService
    def initialize(user:)
      @user = user
    end

    def add!(target_user:)
      @user.favorite_users.find_or_create_by!(target_user: target_user)
    rescue ActiveRecord::RecordNotUnique
      # 同じユーザーの重複登録は成功として扱う。
    end

    def remove!(target_user_id:)
      @user.favorite_users.where(target_user_id: target_user_id).destroy_all
    end
  end
end
