# frozen_string_literal: true

module LpAnalytics
  class AnalysisFilter
    DEFAULT_PERIOD = "last_7_days"
    PERIODS = %w[today last_7_days last_30_days custom].freeze
    MAX_RANGE_DAYS = 366
    DIRECT_VALUE = "__direct__"
    FILTER_ATTRIBUTES = %i[
      traffic_source
      utm_source
      utm_campaign
      utm_content
    ].freeze

    attr_reader :period, :start_date, :end_date, :lp_identifier, :device_type, :warnings

    def initialize(params:, today: Time.zone.today)
      @params = params.to_h.with_indifferent_access
      @today = today
      @warnings = []

      assign_period
      assign_dimensions
    end

    def start_time
      start_date.beginning_of_day
    end

    def end_time
      (end_date + 1.day).beginning_of_day
    end

    def apply(scope = Visit.all)
      filtered = scope.where(started_at: start_time...end_time, lp_identifier: lp_identifier)
      FILTER_ATTRIBUTES.each do |attribute|
        filtered = apply_exact_filter(filtered, attribute, public_send(attribute))
      end
      filtered = filtered.where(device_type: device_type) if device_type.present?
      filtered
    end

    def to_params
      {
        period: period,
        start_date: start_date.iso8601,
        end_date: end_date.iso8601,
        lp_identifier: lp_identifier,
        traffic_source: traffic_source,
        utm_source: utm_source,
        utm_campaign: utm_campaign,
        utm_content: utm_content,
        device_type: device_type
      }.compact_blank
    end

    FILTER_ATTRIBUTES.each do |attribute|
      define_method(attribute) { instance_variable_get("@#{attribute}") }
    end

    private

    attr_reader :params, :today

    def assign_period
      requested_period = params[:period].to_s
      @period = PERIODS.include?(requested_period) ? requested_period : DEFAULT_PERIOD

      if @period == "custom"
        assign_custom_period
      else
        assign_preset_period
      end
    end

    def assign_preset_period
      days = { "today" => 1, "last_7_days" => 7, "last_30_days" => 30 }.fetch(period)
      @start_date = today - (days - 1).days
      @end_date = today
    end

    def assign_custom_period
      parsed_start = parse_date(params[:start_date])
      parsed_end = parse_date(params[:end_date])

      if parsed_start.nil? || parsed_end.nil?
        fall_back_to_default_period("開始日と終了日を正しい日付で指定してください。")
      elsif parsed_start > parsed_end
        fall_back_to_default_period("開始日は終了日以前の日付を指定してください。")
      elsif (parsed_end - parsed_start).to_i + 1 > MAX_RANGE_DAYS
        fall_back_to_default_period("任意期間は#{MAX_RANGE_DAYS}日以内で指定してください。")
      else
        @start_date = parsed_start
        @end_date = parsed_end
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def fall_back_to_default_period(message)
      warnings << message
      @period = DEFAULT_PERIOD
      assign_preset_period
    end

    def assign_dimensions
      requested_lp = normalized_value(params[:lp_identifier])
      @lp_identifier = if requested_lp.blank?
        Configuration::STORE_LP_202607
      elsif Configuration.supported_lp?(requested_lp)
        requested_lp
      else
        warnings << "未対応のLPが指定されたため、対象LPを初期値へ戻しました。"
        Configuration::STORE_LP_202607
      end

      FILTER_ATTRIBUTES.each do |attribute|
        instance_variable_set("@#{attribute}", normalized_filter_value(params[attribute]))
      end

      requested_device = normalized_value(params[:device_type])
      @device_type = if requested_device.blank? || Visit::DEVICE_TYPES.include?(requested_device)
        requested_device
      else
        warnings << "未対応の端末が指定されたため、端末の絞り込みを解除しました。"
        nil
      end
    end

    def normalized_filter_value(value)
      return DIRECT_VALUE if value.to_s == DIRECT_VALUE

      normalized_value(value)
    end

    def normalized_value(value)
      return unless value.is_a?(String)

      value.strip.presence&.slice(0, Visit::TRAFFIC_VALUE_MAX_LENGTH)
    end

    def apply_exact_filter(scope, attribute, value)
      return scope if value.blank?
      return scope.where(attribute => [ nil, "" ]) if value == DIRECT_VALUE

      scope.where(attribute => value)
    end
  end
end
