module StreamSessions
  class CommentsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_stream_session

    def create
      body = params.require(:comment).fetch(:body).to_s

      raise ActiveRecord::RecordInvalid.new(Comment.new) if body.blank?

      # MVP: BANは後で入れるならここで raise でもOK（後述でservice化）
      comment = Comment.create!(
        stream_session: @stream_session,
        booth: @stream_session.booth,
        user: current_user,
        body: body
      )

      CommentNotifier.append(comment)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "comment_form",
            partial: "stream_sessions/comments/form",
            formats: [:html],
            locals: { stream_session: @stream_session }
          )
        end

        format.html { redirect_back fallback_location: root_path }
      end
    end

    private

    def set_stream_session
      @stream_session = StreamSession.find(params[:stream_session_id])
    end
  end
end
