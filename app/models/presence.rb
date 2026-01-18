# frozen_string_literal: true

class Presence < ApplicationRecord
  belongs_to :stream_session
  belongs_to :customer_user, class_name: "User"
end
