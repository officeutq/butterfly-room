# frozen_string_literal: true

module StreamSessions
  class CommentsController < ApplicationController
    include StoreBanGuard

    before_action :authenticate_user!
    before_action :set_stream_session
    before_action :set_comment, only: %i[hide unhide report]
    before_action :reject_banned_customer_for_stream_session!, only: %i[create]
    before_action :ensure_comment_moderator!, only: %i[hide unhide]

    def create
      policy = Authorization::ViewerPolicy.new(current_user, @stream_session)
      head :forbidden and return unless policy.create_comment?

      StreamSessions::Comments::CreateService.new(
        stream_session: @stream_session,
        user: current_user,
        body: params.require(:comment).fetch(:body)
      ).call

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "comment_form",
            partial: "stream_sessions/comments/form",
            formats: [ :html ],
            locals: { stream_session: @stream_session }
          )
        end
        format.html { redirect_back fallback_location: root_path }
      end
    rescue StreamSessions::Comments::CreateService::BoothNotLiveError
      render_comment_form_error("配信中（live/away）のときのみコメントできます", status: :conflict)
    rescue StreamSessions::Comments::CreateService::RateLimitedError
      render_comment_form_error("送信が速すぎます。少し待ってからもう一度送信してください", status: :unprocessable_entity)
    rescue ActiveRecord::RecordInvalid => e
      message = e.record.errors.full_messages.to_sentence.presence || "入力が不正です"
      render_comment_form_error(message, status: :unprocessable_entity)
    rescue ActionController::ParameterMissing, KeyError
      render_comment_form_error("入力が不正です", status: :unprocessable_entity)
    end

    def report
      StreamSessions::Comments::ReportService.new(
        comment: @comment,
        reporter_user: current_user
      ).call

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "flash_inner",
            partial: "shared/flash_message",
            locals: { level: "success", message: "通報しました" }
          )
        end
        format.html { redirect_back fallback_location: root_path, notice: "通報しました", status: :see_other }
      end
    rescue StreamSessions::Comments::ReportService::NotAllowedError
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "flash_inner",
            partial: "shared/flash_message",
            locals: { level: "danger", message: "このコメントは通報できません" }
          ), status: :forbidden
        end
        format.html { redirect_back fallback_location: root_path, alert: "このコメントは通報できません", status: :see_other }
      end
    rescue StreamSessions::Comments::ReportService::AlreadyReportedError
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "flash_inner",
            partial: "shared/flash_message",
            locals: { level: "danger", message: "このコメントはすでに通報済みです" }
          ), status: :unprocessable_entity
        end
        format.html { redirect_back fallback_location: root_path, alert: "このコメントはすでに通報済みです", status: :see_other }
      end
    end

    def hide
      @comment.hide_by!(current_user)
      CommentNotifier.replace(@comment)
      head :ok
    rescue ActiveRecord::RecordInvalid, ArgumentError
      head :unprocessable_entity
    end

    def unhide
      @comment.unhide!
      CommentNotifier.replace(@comment)
      head :ok
    rescue ActiveRecord::RecordInvalid, ArgumentError
      head :unprocessable_entity
    end

    private

    def set_stream_session
      @stream_session = StreamSession.find(params[:stream_session_id])
    end

    def set_comment
      @comment = @stream_session.comments.find(params[:id])
    end

    def reject_banned_customer_for_stream_session!
      reject_banned_customer!(store: @stream_session.store)
    end

    def ensure_comment_moderator!
      head :forbidden unless @stream_session.started_by_cast_user_id == current_user.id
    end

    def render_comment_form_error(message, status:)
      respond_to do |format|
        format.turbo_stream do
          render(
            turbo_stream: turbo_stream.replace(
              "comment_form",
              partial: "stream_sessions/comments/form",
              formats: [ :html ],
              locals: { stream_session: @stream_session, error_message: message }
            ),
            status: status
          )
        end
        format.html { redirect_back fallback_location: root_path, alert: message }
      end
    end
  end
end
