# frozen_string_literal: true

module LpAnalytics
  class AnalysisQuery
    Metric = Data.define(:key, :label, :visit_count, :overall_rate, :previous_rate)
    Kpi = Data.define(:key, :label, :count, :supplement, :rate)
    CtaMetric = Data.define(
      :key,
      :name,
      :position,
      :kind,
      :reached_visit_count,
      :clicked_visit_count,
      :click_count,
      :click_rate
    )
    Result = Data.define(
      :visit_count,
      :kpis,
      :registration_funnel,
      :contact_funnel,
      :scroll_metrics,
      :section_metrics,
      :cta_metrics
    )

    REGISTRATION_CTA_KEYS = Configuration::CTA_DEFINITIONS.filter_map do |key, definition|
      key if definition.fetch(:kind) == :registration
    end.freeze

    def initialize(filter:)
      @filter = filter
    end

    def call
      @visits = filter.apply
      @events = Event.where(lp_analytics_visit_id: visits.select(:id))
      @distinct_counts = grouped_distinct_visit_counts
      @event_counts = grouped_event_counts
      visit_count = visits.count

      Result.new(
        visit_count: visit_count,
        kpis: kpis(visit_count),
        registration_funnel: registration_funnel(visit_count),
        contact_funnel: contact_funnel(visit_count),
        scroll_metrics: scroll_metrics(visit_count),
        section_metrics: section_metrics(visit_count),
        cta_metrics: cta_metrics
      )
    end

    private

    attr_reader :filter, :visits, :events, :distinct_counts, :event_counts

    def grouped_distinct_visit_counts
      events.group(:event_type, :event_value).distinct.count(:lp_analytics_visit_id)
    end

    def grouped_event_counts
      events.group(:event_type, :event_value).count
    end

    def kpis(visit_count)
      registration_completions = event_count("store_registration_complete")
      registration_completion_visits = distinct_count("store_registration_complete")
      contact_completions = event_count("store_contact_complete")
      contact_completion_visits = distinct_count("store_contact_complete")

      [
        Kpi.new(key: :visits, label: "LP訪問数", count: visit_count, supplement: nil, rate: nil),
        Kpi.new(
          key: :cta_clicked_visits,
          label: "CTAクリック訪問数",
          count: distinct_visit_count_for(event_type: "cta_clicked"),
          supplement: nil,
          rate: nil
        ),
        Kpi.new(
          key: :registration_form_visits,
          label: "登録フォーム到達数",
          count: distinct_count("store_registration_form_view"),
          supplement: nil,
          rate: nil
        ),
        Kpi.new(
          key: :registration_completions,
          label: "店舗登録完了件数",
          count: registration_completions,
          supplement: "完了訪問数: #{registration_completion_visits}",
          rate: percentage(registration_completion_visits, visit_count)
        ),
        Kpi.new(
          key: :contact_form_visits,
          label: "お問い合わせフォーム到達数",
          count: distinct_count("store_contact_form_view"),
          supplement: nil,
          rate: nil
        ),
        Kpi.new(
          key: :contact_completions,
          label: "お問い合わせ完了件数",
          count: contact_completions,
          supplement: "完了訪問数: #{contact_completion_visits}",
          rate: percentage(contact_completion_visits, visit_count)
        )
      ]
    end

    def registration_funnel(visit_count)
      sequential_funnel(
        visit_count: visit_count,
        steps: [
          [ :visit, "LP訪問", nil ],
          [ :scroll, "スクロール到達", event_visit_ids(event_type: "scroll_reached") ],
          [ :section, "主要セクション到達", event_visit_ids(event_type: "section_reached") ],
          [
            :registration_cta,
            "店舗登録CTAクリック",
            event_visit_ids(event_type: "cta_clicked", values: REGISTRATION_CTA_KEYS)
          ],
          [
            :registration_form,
            "登録フォーム表示",
            event_visit_ids(event_type: "store_registration_form_view")
          ],
          [
            :registration_complete,
            "店舗登録完了",
            event_visit_ids(event_type: "store_registration_complete")
          ]
        ]
      )
    end

    def contact_funnel(visit_count)
      sequential_funnel(
        visit_count: visit_count,
        steps: [
          [ :visit, "LP訪問", nil ],
          [
            :bottom_reached,
            "最下部付近まで到達",
            event_visit_ids(event_type: "section_reached", values: [ "bottom_cta" ])
          ],
          [
            :contact_cta,
            "お問い合わせCTAクリック",
            event_visit_ids(event_type: "cta_clicked", values: [ "bottom_contact" ])
          ],
          [
            :contact_form,
            "お問い合わせフォーム表示",
            event_visit_ids(event_type: "store_contact_form_view")
          ],
          [
            :contact_complete,
            "お問い合わせ完了",
            event_visit_ids(event_type: "store_contact_complete")
          ]
        ]
      )
    end

    def sequential_funnel(visit_count:, steps:)
      cohort = visits
      previous_count = nil

      steps.map do |key, label, event_ids|
        cohort = cohort.where(id: event_ids) if event_ids
        count = cohort.count
        metric = Metric.new(
          key: key,
          label: label,
          visit_count: count,
          overall_rate: percentage(count, visit_count),
          previous_rate: previous_count.nil? ? nil : percentage(count, previous_count)
        )
        previous_count = count
        metric
      end
    end

    def scroll_metrics(visit_count)
      Configuration::SCROLL_VALUES.map do |value|
        count = distinct_count("scroll_reached", value)
        Metric.new(
          key: value,
          label: "#{value}%",
          visit_count: count,
          overall_rate: percentage(count, visit_count),
          previous_rate: nil
        )
      end
    end

    def section_metrics(visit_count)
      previous_count = nil

      lp_definition.fetch(:sections).map do |section|
        count = distinct_count("section_reached", section)
        metric = Metric.new(
          key: section,
          label: Configuration::SECTION_LABELS.fetch(section),
          visit_count: count,
          overall_rate: percentage(count, visit_count),
          previous_rate: previous_count.nil? ? nil : percentage(count, previous_count)
        )
        previous_count = count
        metric
      end
    end

    def cta_metrics
      lp_definition.fetch(:ctas).map do |key|
        definition = Configuration::CTA_DEFINITIONS.fetch(key)
        reached = distinct_count("cta_reached", key)
        clicked = distinct_count("cta_clicked", key)

        CtaMetric.new(
          key: key,
          name: definition.fetch(:name),
          position: definition.fetch(:position),
          kind: definition.fetch(:kind),
          reached_visit_count: reached,
          clicked_visit_count: clicked,
          click_count: event_count("cta_clicked", key),
          click_rate: percentage(clicked, reached)
        )
      end
    end

    def lp_definition
      Configuration::LP_DEFINITIONS.fetch(filter.lp_identifier)
    end

    def distinct_count(event_type, event_value = nil)
      distinct_counts.fetch([ event_type, event_value ], 0)
    end

    def event_count(event_type, event_value = nil)
      event_counts.fetch([ event_type, event_value ], 0)
    end

    def distinct_visit_count_for(event_type:)
      events.where(event_type: event_type).distinct.count(:lp_analytics_visit_id)
    end

    def event_visit_ids(event_type:, values: nil)
      relation = events.where(event_type: event_type)
      relation = relation.where(event_value: values) if values
      relation.select(:lp_analytics_visit_id)
    end

    def percentage(numerator, denominator)
      return 0.0 if denominator.to_i.zero?

      (numerator.to_f * 100 / denominator).round(2)
    end
  end
end
