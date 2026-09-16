# frozen_string_literal: true

# Run with rails runner after creating the dedicated, empty test database.
database = ActiveRecord::Base.connection_db_config.database
unless Rails.env.test? && database == "butterfly_room_manual_selection"
  raise "Selection screenshots require the isolated butterfly_room_manual_selection test database"
end

Rails.application.load_tasks
result = ManualCapture::DataBuilder.new.call!
result.fetch(:store).update!(published: true)
result.fetch(:secondary_store).update!(published: true)
result.fetch(:booth).update!(description: "店舗のメインブースです。担当キャストとの会話をお楽しみください。")
result.fetch(:secondary_booth).update!(description: "店舗のサブブースです。配信予定や担当キャストをご確認ください。")
closed = Booth.find_or_initialize_by(name: "マニュアル撮影用閉鎖済みブース", store: result.fetch(:store))
closed.assign_attributes(status: :offline, archived_at: Time.current)
closed.save!

puts "Selection capture fixtures prepared in #{database}; no real IVS Stage is used."
