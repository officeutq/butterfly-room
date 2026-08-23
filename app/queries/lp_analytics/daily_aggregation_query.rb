# frozen_string_literal: true

module LpAnalytics
  class DailyAggregationQuery
    ZONE = "Asia/Tokyo"

    Row = Data.define(
      :aggregation_key,
      :aggregation_date,
      :lp_identifier,
      :traffic_source,
      :utm_source,
      :utm_medium,
      :utm_campaign,
      :utm_content,
      :device_type,
      :visit_count,
      :scroll_25_visit_count,
      :scroll_50_visit_count,
      :scroll_75_visit_count,
      :scroll_90_visit_count,
      :section_usage_visit_count,
      :section_usage_rate,
      :section_strengths_visit_count,
      :section_strengths_rate,
      :section_system_visit_count,
      :section_system_rate,
      :section_pricing_visit_count,
      :section_pricing_rate,
      :section_flow_visit_count,
      :section_flow_rate,
      :section_cast_visit_count,
      :section_cast_rate,
      :section_qa_visit_count,
      :section_qa_rate,
      :section_bottom_cta_visit_count,
      :section_bottom_cta_rate,
      :section_existing_customer_opportunity_visit_count,
      :section_existing_customer_opportunity_rate,
      :section_service_introduction_visit_count,
      :section_service_introduction_rate,
      :section_usage_mechanism_visit_count,
      :section_usage_mechanism_rate,
      :section_service_comparison_visit_count,
      :section_service_comparison_rate,
      :section_adoption_cost_visit_count,
      :section_adoption_cost_rate,
      :section_usage_scenes_visit_count,
      :section_usage_scenes_rate,
      :section_getting_started_visit_count,
      :section_getting_started_rate,
      :section_final_opportunity_cta_visit_count,
      :section_final_opportunity_cta_rate,
      :registration_cta_click_visit_count,
      :registration_cta_click_count,
      :registration_form_visit_count,
      :registration_completion_count,
      :registration_completion_visit_count,
      :registration_cv_rate,
      :contact_cta_click_visit_count,
      :contact_form_visit_count,
      :contact_completion_count,
      :contact_completion_visit_count,
      :contact_cv_rate
    )

    SQL = <<~SQL.squish
      WITH selected_visits AS (
        SELECT
          id,
          lp_identifier,
          COALESCE(traffic_source, '') AS traffic_source,
          COALESCE(utm_source, '') AS utm_source,
          COALESCE(utm_medium, '') AS utm_medium,
          COALESCE(utm_campaign, '') AS utm_campaign,
          COALESCE(utm_content, '') AS utm_content,
          device_type
        FROM lp_analytics_visits
        WHERE started_at >= :start_time
          AND started_at < :end_time
          AND lp_identifier = :lp_identifier
      ),
      visit_event_totals AS (
        SELECT
          events.lp_analytics_visit_id,
          COUNT(*) FILTER (WHERE events.event_type = 'scroll_reached' AND events.event_value = '25') AS scroll_25_count,
          COUNT(*) FILTER (WHERE events.event_type = 'scroll_reached' AND events.event_value = '50') AS scroll_50_count,
          COUNT(*) FILTER (WHERE events.event_type = 'scroll_reached' AND events.event_value = '75') AS scroll_75_count,
          COUNT(*) FILTER (WHERE events.event_type = 'scroll_reached' AND events.event_value = '90') AS scroll_90_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'USAGE') AS section_usage_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'STRENGTHS') AS section_strengths_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'SYSTEM') AS section_system_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'PRICING') AS section_pricing_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'FLOW') AS section_flow_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'CAST') AS section_cast_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'QA') AS section_qa_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'bottom_cta') AS section_bottom_cta_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'existing_customer_opportunity') AS section_existing_customer_opportunity_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'service_introduction') AS section_service_introduction_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'usage_mechanism') AS section_usage_mechanism_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'service_comparison') AS section_service_comparison_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'adoption_cost') AS section_adoption_cost_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'usage_scenes') AS section_usage_scenes_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'getting_started') AS section_getting_started_count,
          COUNT(*) FILTER (WHERE events.event_type = 'section_reached' AND events.event_value = 'final_opportunity_cta') AS section_final_opportunity_cta_count,
          COUNT(*) FILTER (
            WHERE events.event_type = 'cta_clicked'
              AND events.event_value IN (:registration_cta_values)
          ) AS registration_cta_click_count,
          COUNT(*) FILTER (WHERE events.event_type = 'store_registration_form_view') AS registration_form_count,
          COUNT(*) FILTER (WHERE events.event_type = 'store_registration_complete') AS registration_completion_count,
          COUNT(*) FILTER (
            WHERE events.event_type = 'cta_clicked'
              AND events.event_value IN (:contact_cta_values)
          ) AS contact_cta_click_count,
          COUNT(*) FILTER (WHERE events.event_type = 'store_contact_form_view') AS contact_form_count,
          COUNT(*) FILTER (WHERE events.event_type = 'store_contact_complete') AS contact_completion_count
        FROM lp_analytics_events events
        INNER JOIN selected_visits visits ON visits.id = events.lp_analytics_visit_id
        GROUP BY events.lp_analytics_visit_id
      )
      SELECT
        visits.lp_identifier,
        visits.traffic_source,
        visits.utm_source,
        visits.utm_medium,
        visits.utm_campaign,
        visits.utm_content,
        visits.device_type,
        COUNT(*) AS visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.scroll_25_count, 0) > 0) AS scroll_25_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.scroll_50_count, 0) > 0) AS scroll_50_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.scroll_75_count, 0) > 0) AS scroll_75_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.scroll_90_count, 0) > 0) AS scroll_90_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_usage_count, 0) > 0) AS section_usage_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_strengths_count, 0) > 0) AS section_strengths_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_system_count, 0) > 0) AS section_system_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_pricing_count, 0) > 0) AS section_pricing_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_flow_count, 0) > 0) AS section_flow_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_cast_count, 0) > 0) AS section_cast_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_qa_count, 0) > 0) AS section_qa_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_bottom_cta_count, 0) > 0) AS section_bottom_cta_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_existing_customer_opportunity_count, 0) > 0) AS section_existing_customer_opportunity_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_service_introduction_count, 0) > 0) AS section_service_introduction_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_usage_mechanism_count, 0) > 0) AS section_usage_mechanism_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_service_comparison_count, 0) > 0) AS section_service_comparison_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_adoption_cost_count, 0) > 0) AS section_adoption_cost_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_usage_scenes_count, 0) > 0) AS section_usage_scenes_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_getting_started_count, 0) > 0) AS section_getting_started_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.section_final_opportunity_cta_count, 0) > 0) AS section_final_opportunity_cta_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.registration_cta_click_count, 0) > 0) AS registration_cta_click_visit_count,
        COALESCE(SUM(totals.registration_cta_click_count), 0) AS registration_cta_click_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.registration_form_count, 0) > 0) AS registration_form_visit_count,
        COALESCE(SUM(totals.registration_completion_count), 0) AS registration_completion_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.registration_completion_count, 0) > 0) AS registration_completion_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.contact_cta_click_count, 0) > 0) AS contact_cta_click_visit_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.contact_form_count, 0) > 0) AS contact_form_visit_count,
        COALESCE(SUM(totals.contact_completion_count), 0) AS contact_completion_count,
        COUNT(*) FILTER (WHERE COALESCE(totals.contact_completion_count, 0) > 0) AS contact_completion_visit_count
      FROM selected_visits visits
      LEFT JOIN visit_event_totals totals ON totals.lp_analytics_visit_id = visits.id
      GROUP BY
        visits.lp_identifier,
        visits.traffic_source,
        visits.utm_source,
        visits.utm_medium,
        visits.utm_campaign,
        visits.utm_content,
        visits.device_type
      ORDER BY
        visits.traffic_source,
        visits.utm_source,
        visits.utm_medium,
        visits.utm_campaign,
        visits.utm_content,
        visits.device_type
    SQL

    def initialize(aggregation_date:, lp_identifier: Configuration::STORE_LP_202607)
      @aggregation_date = strict_date(aggregation_date)
      @lp_identifier = lp_identifier.to_s
      raise ArgumentError, "unsupported LP identifier" unless Configuration.supported_lp?(@lp_identifier)
    end

    def call
      result = ApplicationRecord.connection.select_all(sanitized_sql)
      result.map { |attributes| build_row(attributes) }
    end

    private

    attr_reader :aggregation_date, :lp_identifier

    def sanitized_sql
      ApplicationRecord.sanitize_sql_array([
        SQL,
        {
          start_time: time_at_start_of_day,
          end_time: time_at_end_of_day,
          lp_identifier: lp_identifier,
          registration_cta_values: registration_cta_values,
          contact_cta_values: contact_cta_values
        }
      ])
    end

    def time_at_start_of_day
      Time.use_zone(ZONE) { Time.zone.local(aggregation_date.year, aggregation_date.month, aggregation_date.day) }
    end

    def time_at_end_of_day
      time_at_start_of_day + 1.day
    end

    def registration_cta_values
      Configuration.cta_keys_for(lp_identifier, kind: :registration)
    end

    def contact_cta_values
      Configuration.cta_keys_for(lp_identifier, kind: :contact)
    end

    def build_row(attributes)
      dimensions = {
        aggregation_date: aggregation_date,
        lp_identifier: attributes.fetch("lp_identifier"),
        traffic_source: attributes.fetch("traffic_source"),
        utm_source: attributes.fetch("utm_source"),
        utm_medium: attributes.fetch("utm_medium"),
        utm_campaign: attributes.fetch("utm_campaign"),
        utm_content: attributes.fetch("utm_content"),
        device_type: attributes.fetch("device_type")
      }
      visit_count = attributes.fetch("visit_count").to_i
      section_usage_visits = attributes.fetch("section_usage_visit_count").to_i
      section_strengths_visits = attributes.fetch("section_strengths_visit_count").to_i
      section_system_visits = attributes.fetch("section_system_visit_count").to_i
      section_pricing_visits = attributes.fetch("section_pricing_visit_count").to_i
      section_flow_visits = attributes.fetch("section_flow_visit_count").to_i
      section_cast_visits = attributes.fetch("section_cast_visit_count").to_i
      section_qa_visits = attributes.fetch("section_qa_visit_count").to_i
      section_bottom_cta_visits = attributes.fetch("section_bottom_cta_visit_count").to_i
      section_existing_customer_opportunity_visits = attributes.fetch("section_existing_customer_opportunity_visit_count").to_i
      section_service_introduction_visits = attributes.fetch("section_service_introduction_visit_count").to_i
      section_usage_mechanism_visits = attributes.fetch("section_usage_mechanism_visit_count").to_i
      section_service_comparison_visits = attributes.fetch("section_service_comparison_visit_count").to_i
      section_adoption_cost_visits = attributes.fetch("section_adoption_cost_visit_count").to_i
      section_usage_scenes_visits = attributes.fetch("section_usage_scenes_visit_count").to_i
      section_getting_started_visits = attributes.fetch("section_getting_started_visit_count").to_i
      section_final_opportunity_cta_visits = attributes.fetch("section_final_opportunity_cta_visit_count").to_i
      registration_completion_visits = attributes.fetch("registration_completion_visit_count").to_i
      contact_completion_visits = attributes.fetch("contact_completion_visit_count").to_i

      Row.new(
        aggregation_key: AggregationKey.generate(**dimensions),
        **dimensions,
        visit_count: visit_count,
        scroll_25_visit_count: attributes.fetch("scroll_25_visit_count").to_i,
        scroll_50_visit_count: attributes.fetch("scroll_50_visit_count").to_i,
        scroll_75_visit_count: attributes.fetch("scroll_75_visit_count").to_i,
        scroll_90_visit_count: attributes.fetch("scroll_90_visit_count").to_i,
        section_usage_visit_count: section_usage_visits,
        section_usage_rate: rate(section_usage_visits, visit_count),
        section_strengths_visit_count: section_strengths_visits,
        section_strengths_rate: rate(section_strengths_visits, visit_count),
        section_system_visit_count: section_system_visits,
        section_system_rate: rate(section_system_visits, visit_count),
        section_pricing_visit_count: section_pricing_visits,
        section_pricing_rate: rate(section_pricing_visits, visit_count),
        section_flow_visit_count: section_flow_visits,
        section_flow_rate: rate(section_flow_visits, visit_count),
        section_cast_visit_count: section_cast_visits,
        section_cast_rate: rate(section_cast_visits, visit_count),
        section_qa_visit_count: section_qa_visits,
        section_qa_rate: rate(section_qa_visits, visit_count),
        section_bottom_cta_visit_count: section_bottom_cta_visits,
        section_bottom_cta_rate: rate(section_bottom_cta_visits, visit_count),
        section_existing_customer_opportunity_visit_count: section_existing_customer_opportunity_visits,
        section_existing_customer_opportunity_rate: rate(section_existing_customer_opportunity_visits, visit_count),
        section_service_introduction_visit_count: section_service_introduction_visits,
        section_service_introduction_rate: rate(section_service_introduction_visits, visit_count),
        section_usage_mechanism_visit_count: section_usage_mechanism_visits,
        section_usage_mechanism_rate: rate(section_usage_mechanism_visits, visit_count),
        section_service_comparison_visit_count: section_service_comparison_visits,
        section_service_comparison_rate: rate(section_service_comparison_visits, visit_count),
        section_adoption_cost_visit_count: section_adoption_cost_visits,
        section_adoption_cost_rate: rate(section_adoption_cost_visits, visit_count),
        section_usage_scenes_visit_count: section_usage_scenes_visits,
        section_usage_scenes_rate: rate(section_usage_scenes_visits, visit_count),
        section_getting_started_visit_count: section_getting_started_visits,
        section_getting_started_rate: rate(section_getting_started_visits, visit_count),
        section_final_opportunity_cta_visit_count: section_final_opportunity_cta_visits,
        section_final_opportunity_cta_rate: rate(section_final_opportunity_cta_visits, visit_count),
        registration_cta_click_visit_count: attributes.fetch("registration_cta_click_visit_count").to_i,
        registration_cta_click_count: attributes.fetch("registration_cta_click_count").to_i,
        registration_form_visit_count: attributes.fetch("registration_form_visit_count").to_i,
        registration_completion_count: attributes.fetch("registration_completion_count").to_i,
        registration_completion_visit_count: registration_completion_visits,
        registration_cv_rate: rate(registration_completion_visits, visit_count),
        contact_cta_click_visit_count: attributes.fetch("contact_cta_click_visit_count").to_i,
        contact_form_visit_count: attributes.fetch("contact_form_visit_count").to_i,
        contact_completion_count: attributes.fetch("contact_completion_count").to_i,
        contact_completion_visit_count: contact_completion_visits,
        contact_cv_rate: rate(contact_completion_visits, visit_count)
      )
    end

    def rate(numerator, denominator)
      return 0.0 if denominator.zero?

      (numerator.to_f / denominator).round(8)
    end

    def strict_date(value)
      return value if value.instance_of?(Date)

      raw = value.to_s
      raise Date::Error unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(raw)
    rescue Date::Error
      raise ArgumentError, "aggregation date must be YYYY-MM-DD"
    end
  end
end
