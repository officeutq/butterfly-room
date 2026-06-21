# frozen_string_literal: true

require "test_helper"

class NotificationTagTest < ActiveSupport::TestCase
  test "name is unique at DB level" do
    NotificationTag.create!(name: "maintenance")

    assert_raises(ActiveRecord::RecordNotUnique) do
      NotificationTag.insert_all!([
        { name: "maintenance", created_at: Time.current, updated_at: Time.current }
      ])
    end
  end
end
