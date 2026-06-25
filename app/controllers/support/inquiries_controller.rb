# frozen_string_literal: true

module Support
  class InquiriesController < ApplicationController
    before_action :require_support_user!
    before_action :set_support_context_store, only: %i[new create]
    before_action :set_support_inquiry, only: %i[show]

    def index
      @support_inquiries =
        current_user
          .support_inquiries
          .includes(:store)
          .order(last_message_at: :desc, id: :desc)
    end

    def new
      build_support_inquiry_form
    end

    def create
      result = SupportInquiries::CreateService.new(
        user: current_user,
        store: @support_context_store,
        attributes: support_inquiry_params,
        message_body: support_inquiry_params[:body]
      ).call

      redirect_to support_inquiry_path(result.support_inquiry), notice: "お問い合わせを作成しました"
    rescue ActiveRecord::RecordInvalid => e
      build_support_inquiry_form(
        support_inquiry: e.record,
        message_body: support_inquiry_params[:body]
      )
      render :new, status: :unprocessable_entity
    rescue SupportInquiries::CreateService::NotAllowedError
      head :forbidden
    end

    def show
      @support_inquiry_message = @support_inquiry.support_inquiry_messages.new
      load_support_inquiry_messages
    end

    private

    def require_support_user!
      return if current_user.customer? || current_user.cast? || current_user.store_admin?

      head :forbidden
    end

    def set_support_inquiry
      @support_inquiry =
        current_user
          .support_inquiries
          .includes(:store, :source_comment)
          .find(params[:id])
    end

    def load_support_inquiry_messages
      @support_inquiry_messages =
        @support_inquiry
          .support_inquiry_messages
          .includes(:sender_user)
    end

    def build_support_inquiry_form(support_inquiry: nil, message_body: nil)
      @support_inquiry =
        support_inquiry ||
        current_user.support_inquiries.new(
          category: :question,
          reply_email: current_user.email
        )
      @message_body = message_body
    end

    def support_inquiry_params
      params.require(:support_inquiry).permit(:category, :subject, :reply_email, :body)
    end

    def set_support_context_store
      @support_context_store = support_context_store
    end

    def support_context_store
      return nil if current_user.customer?

      store_from_current_booth || store_from_current_store || single_accessible_store
    end

    def store_from_current_booth
      booth_id = session[:current_booth_id]
      return nil if booth_id.blank?

      booth = Booth.includes(:store).find_by(id: booth_id)
      return nil if booth.blank?
      return booth.store if current_user.store_admin? && current_user.admin_of_store?(booth.store_id)
      return booth.store if current_user.cast? && BoothCast.exists?(booth_id: booth.id, cast_user_id: current_user.id)

      nil
    end

    def store_from_current_store
      return nil unless current_user.store_admin?

      store_id = session[:current_store_id]
      return nil if store_id.blank?

      store = Store.find_by(id: store_id)
      return nil if store.blank?
      return store if current_user.admin_of_store?(store.id)

      nil
    end

    def single_accessible_store
      stores =
        if current_user.store_admin?
          Store
            .joins(:store_memberships)
            .where(store_memberships: {
              user_id: current_user.id,
              membership_role: StoreMembership.membership_roles[:admin]
            })
            .distinct
            .order(:id)
            .to_a
        elsif current_user.cast?
          Store
            .joins(booths: :booth_casts)
            .where(booth_casts: { cast_user_id: current_user.id })
            .distinct
            .order(:id)
            .to_a
        else
          []
        end

      stores.one? ? stores.first : nil
    end
  end
end
