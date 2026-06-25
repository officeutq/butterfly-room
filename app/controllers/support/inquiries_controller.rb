# frozen_string_literal: true

module Support
  class InquiriesController < ApplicationController
    before_action :require_support_user!
    before_action :set_support_context_store, only: %i[new create]
    before_action :set_support_source_comment, only: %i[new create]
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
        source_comment: @support_source_comment,
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
      apply_source_comment_defaults if @support_source_comment.present? && support_inquiry.blank?
      @support_source_comment ||= @support_inquiry.source_comment
      @message_body = message_body.nil? ? default_message_body : message_body
    end

    def support_inquiry_params
      params.require(:support_inquiry).permit(:category, :subject, :reply_email, :body, :source_comment_id)
    end

    def set_support_context_store
      @support_context_store = support_context_store
    end

    def set_support_source_comment
      source_comment_id = source_comment_id_param
      return if source_comment_id.blank?

      unless current_user.store_admin? && @support_context_store.present?
        head :forbidden
        return
      end

      @support_source_comment =
        Comment
          .includes(:user, :booth, stream_session: :store)
          .joins(:stream_session)
          .where(stream_sessions: { store_id: @support_context_store.id })
          .find(source_comment_id)

      @support_context_store = @support_source_comment.stream_session.store
    end

    def source_comment_id_param
      params[:source_comment_id].presence || params.dig(:support_inquiry, :source_comment_id).presence
    end

    def apply_source_comment_defaults
      @support_inquiry.category = :report
      @support_inquiry.subject = "通報に関する運営報告"
      @support_inquiry.source_comment = @support_source_comment
    end

    def default_message_body
      return nil if @support_source_comment.blank?

      source_comment_draft_body(@support_source_comment)
    end

    def source_comment_draft_body(comment)
      stream_session = comment.stream_session
      reported_user = comment.user
      title = stream_session.title.presence || comment.booth&.name.presence || "(no name)"
      reported_user_name = reported_user.display_name.presence || reported_user.email
      reported_user_role = helpers.role_label_for(reported_user.role)

      <<~BODY.chomp
        以下の通報について、運営への確認・対応を依頼します。

        店舗名: #{stream_session.store.name}
        配信名: #{title}
        comment ID: #{comment.id}
        通報されたユーザー: #{reported_user_name}
        ロール: #{reported_user_role}
        コメント本文:
        #{comment.body.presence || "（本文なし）"}

        補足:
      BODY
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
