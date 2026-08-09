# frozen_string_literal: true

class CreateLpAnalyticsVisitsAndEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :lp_analytics_visits do |t|
      t.uuid :public_id, null: false
      t.string :lp_identifier, null: false, limit: 100
      t.string :traffic_source, limit: 100
      t.string :utm_source, limit: 100
      t.string :utm_medium, limit: 100
      t.string :utm_campaign, limit: 100
      t.string :utm_content, limit: 100
      t.string :referral_code, limit: 100
      t.string :device_type, null: false, limit: 20
      t.string :browser_type, limit: 20
      t.datetime :started_at, null: false
      t.datetime :last_activity_at, null: false
      t.timestamps
    end

    add_index :lp_analytics_visits, :public_id, unique: true
    add_index :lp_analytics_visits, %i[lp_identifier started_at]
    add_index :lp_analytics_visits,
              %i[lp_identifier traffic_source started_at],
              name: "idx_lp_analytics_visits_source_started_at"
    add_index :lp_analytics_visits,
              %i[lp_identifier utm_source started_at],
              name: "idx_lp_analytics_visits_utm_source_started_at"
    add_index :lp_analytics_visits,
              %i[lp_identifier utm_medium started_at],
              name: "idx_lp_analytics_visits_utm_medium_started_at"
    add_index :lp_analytics_visits,
              %i[lp_identifier utm_campaign started_at],
              name: "idx_lp_analytics_visits_utm_campaign_started_at"
    add_index :lp_analytics_visits,
              %i[lp_identifier utm_content started_at],
              name: "idx_lp_analytics_visits_utm_content_started_at"
    add_index :lp_analytics_visits,
              %i[lp_identifier device_type started_at],
              name: "idx_lp_analytics_visits_device_started_at"

    create_table :lp_analytics_events do |t|
      t.references :lp_analytics_visit, null: false, foreign_key: true
      t.string :event_type, null: false, limit: 50
      t.string :event_value, limit: 100
      t.string :lp_identifier, null: false, limit: 100
      t.datetime :occurred_at, null: false
      t.uuid :browser_event_id
      t.string :dedupe_key, limit: 64
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :lp_analytics_events,
              %i[lp_analytics_visit_id event_type event_value],
              name: "idx_lp_analytics_events_visit_type_value"
    add_index :lp_analytics_events, :occurred_at
    add_index :lp_analytics_events, %i[lp_identifier occurred_at]
    add_index :lp_analytics_events,
              :browser_event_id,
              unique: true,
              where: "browser_event_id IS NOT NULL",
              name: "uniq_lp_analytics_events_browser_event_id"
    add_index :lp_analytics_events,
              %i[lp_analytics_visit_id dedupe_key],
              unique: true,
              where: "dedupe_key IS NOT NULL",
              name: "uniq_lp_analytics_events_visit_dedupe_key"
  end
end
