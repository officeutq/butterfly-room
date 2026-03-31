# frozen_string_literal: true

module Admin
  class CommentReportsController < BaseController
    before_action :require_current_store!

    def index
      @include_resolved = params[:with_resolved].present?
      @report_cards = report_cards_for_current_store
    end

    def reject
      @include_resolved = params[:with_resolved].present?
      comment = find_comment_for_current_store!

      Admin::CommentReports::RejectService.new(
        comment: comment,
        current_store: current_store
      ).call

      card = build_report_card(comment.id)

      respond_to do |format|
        format.turbo_stream do
          if @include_resolved
            render turbo_stream: turbo_stream.replace(
              helpers.dom_id(comment, :report_card),
              partial: "admin/comment_reports/card",
              locals: { card: card }
            )
          else
            render turbo_stream: turbo_stream.remove(
              helpers.dom_id(comment, :report_card)
            )
          end
        end

        format.html do
          redirect_to admin_comment_reports_path(with_resolved: params[:with_resolved].presence),
                      notice: "通報を却下しました"
        end
      end
    end

    def ban
      @include_resolved = params[:with_resolved].present?
      comment = find_comment_for_current_store!

      Admin::CommentReports::BanService.new(
        comment: comment,
        actor: current_user,
        current_store: current_store
      ).call

      related_comment_ids = report_comment_ids_for_reported_user(comment.user_id)

      respond_to do |format|
        format.turbo_stream do
          if @include_resolved
            render turbo_stream: turbo_streams_for_reported_user_replace(related_comment_ids)
          else
            render turbo_stream: turbo_streams_for_reported_user_remove(related_comment_ids)
          end
        end

        format.html do
          redirect_to admin_comment_reports_path(with_resolved: params[:with_resolved].presence),
                      notice: "BANしました"
        end
      end
    end

    private

    ReportAggregate = Struct.new(
      :comment_id,
      :reports_count,
      :pending_count,
      :resolved_count,
      :rejected_count,
      :latest_reported_at,
      keyword_init: true
    ) do
      def status_key
        return "pending" if pending_count.to_i.positive?
        return "resolved" if resolved_count.to_i.positive? && rejected_count.to_i.zero?
        return "rejected" if rejected_count.to_i.positive? && resolved_count.to_i.zero?

        "mixed"
      end
    end

    def report_cards_for_current_store
      aggregates = aggregated_reports_for_current_store
      comments_by_id = preload_comments(aggregates.map(&:comment_id))
      banned_user_ids = banned_customer_user_ids(comments_by_id.values)

      cards =
        aggregates.filter_map do |aggregate|
          build_report_card_from(
            aggregate: aggregate,
            comment: comments_by_id[aggregate.comment_id],
            banned_user_ids: banned_user_ids
          )
        end

      cards.select do |card|
        next true if @include_resolved

        card[:status_key] == "pending" && !card[:banned]
      end
    end

    def build_report_card(comment_id)
      aggregate = aggregated_reports_for_current_store.find { |row| row.comment_id == comment_id }
      return nil if aggregate.blank?

      comment = preload_comments([ comment_id ])[comment_id]
      return nil if comment.blank?

      banned_user_ids = banned_customer_user_ids([ comment ])

      build_report_card_from(
        aggregate: aggregate,
        comment: comment,
        banned_user_ids: banned_user_ids
      )
    end

    def build_report_card_from(aggregate:, comment:, banned_user_ids:)
      return nil if comment.blank?

      reported_user = comment.user
      banned = banned_user_ids.include?(reported_user.id)

      {
        comment: comment,
        reports_count: aggregate.reports_count.to_i,
        status_key: aggregate.status_key,
        latest_reported_at: aggregate.latest_reported_at,
        banned: banned,
        reportable_to_ops: !reported_user.customer?
      }
    end

    def banned_customer_user_ids(comments)
      user_ids = comments.filter_map { |comment| comment.user_id }.uniq
      return [] if user_ids.empty?

      current_store.store_bans.where(customer_user_id: user_ids).pluck(:customer_user_id)
    end

    def report_comment_ids_for_reported_user(reported_user_id)
      CommentReport
        .where(store_id: current_store.id, reported_user_id: reported_user_id)
        .distinct
        .pluck(:comment_id)
    end

    def turbo_streams_for_reported_user_replace(comment_ids)
      comment_ids.filter_map do |comment_id|
        card = build_report_card(comment_id)
        next if card.blank?

        turbo_stream.replace(
          helpers.dom_id(card[:comment], :report_card),
          partial: "admin/comment_reports/card",
          locals: { card: card }
        )
      end
    end

    def turbo_streams_for_reported_user_remove(comment_ids)
      comment_ids.map do |comment_id|
        turbo_stream.remove(
          helpers.dom_id(Comment.new(id: comment_id), :report_card)
        )
      end
    end

    def find_comment_for_current_store!
      Comment
        .joins(:stream_session)
        .where(stream_sessions: { store_id: current_store.id })
        .find(params[:id])
    end

    def aggregated_reports_for_current_store
      pending_status = quoted_comment_report_status(:pending)
      resolved_status = quoted_comment_report_status(:resolved)
      rejected_status = quoted_comment_report_status(:rejected)

      CommentReport
        .where(store_id: current_store.id)
        .group(:comment_id)
        .select(
          :comment_id,
          Arel.sql("COUNT(*) AS reports_count"),
          Arel.sql("SUM(CASE WHEN status = #{pending_status} THEN 1 ELSE 0 END) AS pending_count"),
          Arel.sql("SUM(CASE WHEN status = #{resolved_status} THEN 1 ELSE 0 END) AS resolved_count"),
          Arel.sql("SUM(CASE WHEN status = #{rejected_status} THEN 1 ELSE 0 END) AS rejected_count"),
          Arel.sql("MAX(created_at) AS latest_reported_at")
        )
        .order(
          Arel.sql(<<~SQL.squish)
            CASE
              WHEN SUM(CASE WHEN status = #{pending_status} THEN 1 ELSE 0 END) > 0 THEN 0
              ELSE 1
            END ASC,
            MAX(created_at) DESC
          SQL
        )
        .map do |row|
          ReportAggregate.new(
            comment_id: row.comment_id,
            reports_count: row.read_attribute(:reports_count),
            pending_count: row.read_attribute(:pending_count),
            resolved_count: row.read_attribute(:resolved_count),
            rejected_count: row.read_attribute(:rejected_count),
            latest_reported_at: row.read_attribute(:latest_reported_at)
          )
        end
    end

    def quoted_comment_report_status(status_key)
      CommentReport.connection.quote(CommentReport.statuses.fetch(status_key))
    end

    def preload_comments(comment_ids)
      Comment
        .where(id: comment_ids)
        .includes(
          :user,
          stream_session: [ :booth, :started_by_cast_user ]
        )
        .index_by(&:id)
    end
  end
end
