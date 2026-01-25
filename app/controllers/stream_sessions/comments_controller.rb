# frozen_string_literal: true

module StreamSessions
  class CommentsController < ApplicationController
    include StoreBanGuard

    before_action :authenticate_user!
    before_action :set_stream_session
    before_action :reject_banned_customer_for_stream_session!

    def create
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
    rescue StreamSessions::Comments::CreateService::RateLimitedError
      render_comment_form_error("送信が速すぎます。少し待ってからもう一度送信してください")
    rescue ActionController::ParameterMissing, KeyError
      render_comment_form_error("入力が不正です")
    end

    private

    def set_stream_session
      @stream_session = StreamSession.find(params[:stream_session_id])
    end

    def reject_banned_customer_for_stream_session!
      reject_banned_customer!(store: @stream_session.store)
    end

    def render_comment_form_error(message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "comment_form",
            partial: "stream_sessions/comments/form",
            formats: [ :html ],
            locals: { stream_session: @stream_session, error_message: message }
          )
        end
        format.html { redirect_back fallback_location: root_path, alert: message }
      end
    end
  end
end
