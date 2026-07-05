# frozen_string_literal: true

class StoreContactSubmission < ApplicationRecord
  NAME_MAX_LENGTH = 120
  STORE_NAME_MAX_LENGTH = 120
  EMAIL_MAX_LENGTH = 255
  PHONE_NUMBER_MAX_LENGTH = 50
  BODY_MAX_LENGTH = 5_000
  CONTACTABLE_TIME_MAX_LENGTH = 120
  SOURCE_MAX_LENGTH = 50
  SOURCE_STORES_LP = "stores_lp"

  attribute :source, :string, default: SOURCE_STORES_LP

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :store_name, presence: true, length: { maximum: STORE_NAME_MAX_LENGTH }
  validates :email,
    presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    length: { maximum: EMAIL_MAX_LENGTH }
  validates :phone_number, presence: true, length: { maximum: PHONE_NUMBER_MAX_LENGTH }
  validates :body, length: { maximum: BODY_MAX_LENGTH }, allow_blank: true
  validates :contactable_time, length: { maximum: CONTACTABLE_TIME_MAX_LENGTH }, allow_blank: true
  validates :source, presence: true, length: { maximum: SOURCE_MAX_LENGTH }
end
