# frozen_string_literal: true

module LpAnalytics
  class RecentConversionsQuery
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 100

    Page = Data.define(:records, :current_page, :total_pages, :total_count, :per_page) do
      def previous_page
        current_page - 1 if current_page > 1
      end

      def next_page
        current_page + 1 if current_page < total_pages
      end
    end

    def initialize(filter:, page: 1, per_page: DEFAULT_PER_PAGE)
      @filter = filter
      @requested_page = positive_integer(page, default: 1)
      @per_page = [ positive_integer(per_page, default: DEFAULT_PER_PAGE), MAX_PER_PAGE ].min
    end

    def call
      relation = completion_events
      total_count = relation.count
      total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
      current_page = [ requested_page, total_pages ].min
      records = relation
        .order(occurred_at: :desc, id: :desc)
        .limit(per_page)
        .offset((current_page - 1) * per_page)
        .preload(:visit)
        .to_a

      Page.new(
        records: records,
        current_page: current_page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: per_page
      )
    end

    private

    attr_reader :filter, :requested_page, :per_page

    def completion_events
      visit_ids = filter.apply.select(:id)
      Event.where(
        lp_analytics_visit_id: visit_ids,
        event_type: Event::COMPLETION_EVENT_RECORD_TYPES.keys
      )
    end

    def positive_integer(value, default:)
      parsed = Integer(value, exception: false)
      parsed&.positive? ? parsed : default
    end
  end
end
