# frozen_string_literal: true

class AddLpAnalyticsCompletionLinks < ActiveRecord::Migration[8.1]
  def change
    add_reference :stores,
      :lp_analytics_visit,
      foreign_key: true,
      index: true
    add_reference :store_contact_submissions,
      :lp_analytics_visit,
      foreign_key: true,
      index: true

    add_column :lp_analytics_events, :completion_record_type, :string
    add_column :lp_analytics_events, :completion_record_id, :bigint
    add_index :lp_analytics_events,
      %i[completion_record_type completion_record_id],
      unique: true,
      where: "completion_record_type IS NOT NULL AND completion_record_id IS NOT NULL",
      name: "uniq_lp_analytics_events_completion_record"
  end
end
