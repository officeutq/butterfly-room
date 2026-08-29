class CommentNotifier
  def self.append(comment)
    Turbo::StreamsChannel.broadcast_append_to(
      [ comment.stream_session, :comments ],
      target: "comments",
      partial: "comments/comment",
      locals: { comment: comment }
    )

    Turbo::StreamsChannel.broadcast_append_to(
      [ comment.stream_session, :comments, :guest ],
      target: "comments",
      partial: "comments/comment",
      locals: { comment: comment, guest_viewer: true }
    )
  end

  def self.replace(comment)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ comment.stream_session, :comments ],
      target: "comment_#{comment.id}",
      partial: "comments/comment",
      locals: { comment: comment }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ comment.stream_session, :comments, :guest ],
      target: "comment_#{comment.id}",
      partial: "comments/comment",
      locals: { comment: comment, guest_viewer: true }
    )
  end
end
