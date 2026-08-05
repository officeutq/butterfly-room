# frozen_string_literal: true

module SystemAdmin
  class UserPermissionsController < SystemAdmin::BaseController
    before_action :set_user_permission, only: :destroy

    def index
      @user_permissions = UserPermission.includes(:user).order(created_at: :desc, id: :desc)
    end

    def new
      @user_permission = UserPermission.new
      set_permission_options
    end

    def create
      attributes = user_permission_params
      email = attributes.delete(:user_email).to_s.strip.downcase
      user = User.find_by(email: email)

      @user_permission = UserPermission.new(attributes.merge(user: user))
      @user_permission.user_email = email
      @user_permission.errors.add(:user_email, "に一致するユーザーが見つかりません") if user.blank?
      set_permission_options

      if @user_permission.errors.empty? && @user_permission.save
        redirect_to system_admin_user_permissions_path, notice: "追加権限を付与しました"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      @user_permission.destroy!
      redirect_to system_admin_user_permissions_path, notice: "追加権限を削除しました"
    end

    private

    def set_user_permission
      @user_permission = UserPermission.find(params[:id])
    end

    def user_permission_params
      params.require(:user_permission).permit(:user_email, :permission_type)
    end

    def set_permission_options
      @permission_options = UserPermission.select_options
    end
  end
end
