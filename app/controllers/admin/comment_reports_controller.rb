# frozen_string_literal: true

module Admin
  class CommentReportsController < BaseController
    before_action :require_current_store!

    def index
      @include_resolved = params[:with_resolved].present?

      aggregates = aggregated_reports_for_current_store
      comments_by_id = preload_comments(aggregates.map(&:comment_id))

      @report_cards =
        aggregates.filter_map do |aggregate|
          comment = comments_by_id[aggregate.comment_id]
          next if comment.blank?

          {
            comment: comment,
            reports_count: aggregate.reports_count.to_i,
            status_key: aggregate.status_key,
            latest_reported_at: aggregate.latest_reported_at
          }
        end

      @report_cards =
        @report_cards.select do |card|
          @include_resolved || card[:status_key] == "pending"
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
