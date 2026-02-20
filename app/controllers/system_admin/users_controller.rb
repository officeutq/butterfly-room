# frozen_string_literal: true

module SystemAdmin
  class UsersController < SystemAdmin::BaseController
    before_action :set_user, only: %i[edit update destroy]

    def index
      @users = User.order(id: :desc)
    end

    def new
      @user = User.new
      @role_options = role_options
      @role_editable = true
    end

    def create
      @user = User.new(create_user_params)
      @role_options = role_options
      @role_editable = true

      role_value = params.dig(:user, :role).to_s

      unless @role_options.include?(role_value)
        @user.errors.add(:role, "選択できません")
        render :new, status: :unprocessable_entity
        return
      end

      if store_admin_role_requested?(role_value)
        @user.errors.add(:role, "store_admin は選択できません")
        render :new, status: :unprocessable_entity
        return
      end

      @user.role = role_value

      if @user.save
        redirect_to system_admin_users_path, notice: "ユーザーを作成しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @role_options = role_options
      @role_editable = role_editable?(@user)
    end

    def update
      @role_options = role_options
      @role_editable = role_editable?(@user)

      attrs = update_user_params.to_h
      if attrs["password"].blank?
        attrs.delete("password")
        attrs.delete("password_confirmation")
      end

      requested_role = params.dig(:user, :role)

      if requested_role.present?
        requested_role = requested_role.to_s

        unless @role_options.include?(requested_role)
          @user.errors.add(:role, "選択できません")
          render :edit, status: :unprocessable_entity
          return
        end

        if store_admin_role_requested?(requested_role)
          @user.errors.add(:role, "store_admin は選択できません")
          render :edit, status: :unprocessable_entity
          return
        end

        if demote_self?(requested_role)
          @user.errors.add(:base, "自分自身の role を system_admin 以外へ変更できません")
          render :edit, status: :unprocessable_entity
          return
        end

        if demote_last_system_admin?(@user, requested_role)
          @user.errors.add(:base, "最後の system_admin を system_admin 以外へ変更できません")
          render :edit, status: :unprocessable_entity
          return
        end

        # UI側で disabled でも、サーバ側で最終的に抑止（安全側）
        if !@role_editable
          @user.errors.add(:base, "このユーザーの role は変更できません")
          render :edit, status: :unprocessable_entity
          return
        end

        @user.role = requested_role
      end

      if @user.update(attrs)
        redirect_to system_admin_users_path, notice: "更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # 停止（soft delete）
    def destroy
      if @user.deleted?
        redirect_to system_admin_users_path, notice: "すでに停止済みです"
        return
      end

      if @user == current_user
        @user.errors.add(:base, "自分自身を停止できません")
        @role_options = role_options
        @role_editable = role_editable?(@user)
        render :edit, status: :unprocessable_entity
        return
      end

      @user.update!(deleted_at: Time.current)
      redirect_to system_admin_users_path, notice: "ユーザーを停止しました"
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def create_user_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end

    def update_user_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end

    def role_options
      # store_admin を除外
      User.roles.keys.reject { |r| r == "store_admin" }
    end

    def store_admin_role_requested?(role_value)
      role_value.to_s == "store_admin"
    end

    def demote_self?(requested_role)
      @user == current_user && requested_role.to_s != "system_admin"
    end

    def demote_last_system_admin?(target_user, requested_role)
      return false if requested_role.to_s == "system_admin"
      return false unless target_user.system_admin?

      # system_admin がこの1人だけなら降格不可
      system_admin_count = User.where(role: User.roles[:system_admin]).where(deleted_at: nil).count
      system_admin_count <= 1
    end

    def role_editable?(target_user)
      return false if target_user == current_user

      # 最後の system_admin の role は触らせない（UIでも抑止）
      if target_user.system_admin?
        system_admin_count = User.where(role: User.roles[:system_admin]).where(deleted_at: nil).count
        return false if system_admin_count <= 1
      end

      true
    end
  end
end
