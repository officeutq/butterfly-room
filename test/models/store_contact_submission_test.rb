# frozen_string_literal: true

require "test_helper"

class StoreContactSubmissionTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    assert build_submission.valid?
  end

  test "name must be present" do
    submission = build_submission(name: nil)

    assert_not submission.valid?
    assert submission.errors.details[:name].any? { |detail| detail[:error] == :blank }
  end

  test "store name must be present" do
    submission = build_submission(store_name: nil)

    assert_not submission.valid?
    assert submission.errors.details[:store_name].any? { |detail| detail[:error] == :blank }
  end

  test "email must be present" do
    submission = build_submission(email: nil)

    assert_not submission.valid?
    assert submission.errors.details[:email].any? { |detail| detail[:error] == :blank }
  end

  test "email must have valid format" do
    submission = build_submission(email: "invalid-email")

    assert_not submission.valid?
    assert submission.errors.details[:email].any? { |detail| detail[:error] == :invalid }
  end

  test "phone number must be present" do
    submission = build_submission(phone_number: nil)

    assert_not submission.valid?
    assert submission.errors.details[:phone_number].any? { |detail| detail[:error] == :blank }
  end

  test "phone number does not require strict format" do
    submission = build_submission(phone_number: "090-1234-ABCD")

    assert submission.valid?
  end

  test "body is optional" do
    assert build_submission(body: nil).valid?
    assert build_submission(body: "").valid?
  end

  test "contactable time is optional" do
    assert build_submission(contactable_time: nil).valid?
    assert build_submission(contactable_time: "").valid?
  end

  test "source must be present" do
    submission = build_submission(source: nil)

    assert_not submission.valid?
    assert submission.errors.details[:source].any? { |detail| detail[:error] == :blank }
  end

  test "source defaults to stores lp and is saved" do
    submission = StoreContactSubmission.create!(valid_attributes)

    assert_equal StoreContactSubmission::SOURCE_STORES_LP, submission.reload.source
  end

  test "string attributes have maximum lengths" do
    length_limits = {
      name: StoreContactSubmission::NAME_MAX_LENGTH,
      store_name: StoreContactSubmission::STORE_NAME_MAX_LENGTH,
      email: StoreContactSubmission::EMAIL_MAX_LENGTH,
      phone_number: StoreContactSubmission::PHONE_NUMBER_MAX_LENGTH,
      body: StoreContactSubmission::BODY_MAX_LENGTH,
      contactable_time: StoreContactSubmission::CONTACTABLE_TIME_MAX_LENGTH,
      source: StoreContactSubmission::SOURCE_MAX_LENGTH
    }

    length_limits.each do |attribute, max_length|
      submission = build_submission(attribute => value_over_limit_for(attribute, max_length))

      assert_not submission.valid?, "#{attribute} should have a maximum length"
      assert submission.errors.details[attribute].any? { |detail| detail[:error] == :too_long }
    end
  end

  private

  def build_submission(attributes = {})
    StoreContactSubmission.new(
      valid_attributes
        .merge(source: StoreContactSubmission::SOURCE_STORES_LP)
        .merge(attributes)
    )
  end

  def valid_attributes
    {
      name: "Owner Name",
      store_name: "Sample Store",
      email: "owner@example.com",
      phone_number: "090-1234-5678",
      body: "I would like to know more about registration.",
      contactable_time: "Weekdays 10:00-18:00"
    }
  end

  def value_over_limit_for(attribute, max_length)
    return "#{"a" * (max_length - "@example.com".length + 1)}@example.com" if attribute == :email

    "a" * (max_length + 1)
  end
end
