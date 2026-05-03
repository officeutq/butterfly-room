module Favorites
  class UsersController < ApplicationController
    before_action -> { require_at_least!(:customer) }
    before_action :set_user, only: %i[create destroy]

    def index
      @q = params[:q].to_s.strip

      scope =
        current_user
          .favorite_users
          .joins(:target_user)
          .includes(target_user: [ { avatar_attachment: :blob } ])
          .order(created_at: :desc, id: :desc)

      if @q.present?
        q_like = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.where("users.display_name ILIKE :q OR users.bio ILIKE :q", q: q_like)
      end

      @favorite_users = scope
      @favorite_user_ids = @favorite_users.map(&:target_user_id).to_set
    end

    def create
      current_user.favorite_users.find_or_create_by!(target_user: @user)
      render_favorite_button(favorited: true)
    rescue ActiveRecord::RecordNotUnique
      render_favorite_button(favorited: true)
    end

    def destroy
      current_user.favorite_users.where(target_user: @user).destroy_all
      render_favorite_button(favorited: false)
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    end

    def render_favorite_button(favorited:)
      respond_to do |format|
        format.turbo_stream do
          home_dom_id = params[:dom_id].presence || "user_#{@user.id}_favorite_button"

          streams = [
            turbo_stream.replace(
              "user_favorite_button",
              partial: "favorites/users/button_user_show",
              locals: { user: @user, favorited: favorited }
            ),
            turbo_stream.replace(
              home_dom_id,
              partial: "favorites/users/button_home",
              locals: { user: @user, favorited: favorited, dom_id: home_dom_id }
            )
          ]
          render turbo_stream: streams
        end

        format.html { redirect_back fallback_location: user_path(@user) }
      end
    end
  end
end
