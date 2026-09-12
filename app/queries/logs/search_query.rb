# frozen_string_literal: true

module Logs
  class SearchQuery
    PER_PAGE = 50
    MAX_PAGE = 1000
    FILTER_KEYS = %w[from to actor_user_id store_id source request_id archive severity exception_class target_type target_id change_action page].freeze
    COMMON_COLUMNS = %i[id occurred_at actor_user_id store_id source request_id archived_at].freeze
    Page = Data.define(:records, :current_page, :has_next, :errors, :filters)

    def initialize(kind:, filters: {})
      @model = { errors: ErrorLog, changes: ChangeLog }.fetch(kind)
      @errors = []
      @filters = filters.to_h.stringify_keys.slice(*FILTER_KEYS).transform_values do |value|
        if value.nil? || value.is_a?(String) || value.is_a?(Integer)
          value.to_s
        else
          @errors << "検索条件は1項目につき1つの値を指定してください。"
          ""
        end
      end
      @filters["from"] = @filters["from"].presence || (Time.current.in_time_zone("Asia/Tokyo").to_date - 6).iso8601
      @filters["to"] = @filters["to"].presence || Time.current.in_time_zone("Asia/Tokyo").to_date.iso8601
      @filters["archive"] = @filters["archive"].presence || "active"
    end

    def call
      relation = filter_period(@model.all)
      relation = filter_enum(relation, "archive", %w[active archived all])
      relation = relation.where(archived_at: nil) if @filters["archive"] == "active"
      relation = relation.where.not(archived_at: nil) if @filters["archive"] == "archived"
      %w[actor_user_id store_id].each { |field| relation = filter_id(relation, field) }
      relation = filter_enum(relation, "source", LogEntry::SOURCES)
      relation = filter_text(relation, "request_id", /\A[a-zA-Z0-9_-]{1,100}\z/)
      if @model == ErrorLog
        relation = filter_enum(relation, "severity", ErrorLog::SEVERITIES)
        relation = filter_text(relation, "exception_class", /\A[A-Z][A-Za-z0-9_:]{0,199}\z/)
      else
        relation = filter_enum(relation, "target_type", ChangeLog::TARGET_TYPES)
        relation = filter_enum(relation, "change_action", ChangeLog::ACTIONS)
        relation = filter_id(relation, "target_id")
      end
      page = Integer(@filters["page"].presence || "1", exception: false)
      @errors << "ページは1〜#{MAX_PAGE}を指定してください。" unless page && (1..MAX_PAGE).cover?(page)
      records = []
      if @errors.empty?
        columns = COMMON_COLUMNS + (@model == ErrorLog ? %i[severity exception_class handled] : %i[target_type target_id action])
        records = relation.select(*columns).order(occurred_at: :desc, id: :desc)
          .limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE).preload(:actor_user).to_a
      end
      Page.new(records: records.first(PER_PAGE), current_page: page || 1,
        has_next: records.size > PER_PAGE, errors: @errors, filters: @filters)
    end

    private

    def filter_period(relation)
      from = parse_date(@filters["from"])
      to = parse_date(@filters["to"])
      unless from && to && (0..365).cover?((to - from).to_i)
        @errors << "期間は開始日から終了日まで366日以内で指定してください（YYYY-MM-DD）。"
        return relation
      end
      relation.where(occurred_at: from.in_time_zone("Asia/Tokyo")...(to + 1).in_time_zone("Asia/Tokyo"))
    end

    def parse_date(value)
      Date.iso8601(value) if value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && value[0, 4].to_i.positive?
    rescue Date::Error
      nil
    end

    def filter_id(relation, field)
      value = @filters[field]
      return relation if value.blank?

      id = Sanitizer.positive_id(value) if value.match?(/\A[0-9]{1,19}\z/)
      if id
        relation.where(field => id)
      else
        @errors << "#{field}には有効な正の整数を指定してください。"
        relation
      end
    end

    def filter_enum(relation, field, allowed)
      value = @filters[field]
      return relation if value.blank?

      if allowed.include?(value)
        field == "archive" ? relation : relation.where((field == "change_action" ? "action" : field) => value)
      else
        @errors << "#{field}の選択が不正です。"
        relation
      end
    end

    def filter_text(relation, field, format)
      value = @filters[field]
      return relation if value.blank?

      if value.match?(format)
        relation.where(field => value)
      else
        @errors << "#{field}の形式が不正です。"
        relation
      end
    end
  end
end
