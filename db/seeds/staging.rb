# frozen_string_literal: true

raise "staging seed requires APP_ENV=staging" unless ENV["APP_ENV"] == "staging"

store = Store.find_or_create_by!(name: "Butterfly Room Staging")
booth = store.booths.find_or_create_by!(name: "Staging Booth")

puts "seeded staging store id=#{store.id} booth id=#{booth.id}"
