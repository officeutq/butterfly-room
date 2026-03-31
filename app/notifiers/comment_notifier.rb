class CommentNotifier
  def self.append(comment)
    Turbo::StreamsChannel.broadcast_append_to(
      [ comment.stream_session, :comments ],
      target: "comments",
      partial: "comments/comment",
      locals: { comment: comment }
    )
  end

  def self.replace(comment)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ comment.stream_session, :comments ],
      target: "comment_#{comment.id}",
      partial: "comments/comment",
      locals: { comment: comment }
    )
  end
end
