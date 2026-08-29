# frozen_string_literal: true

require "test_helper"

class LegalPagesTest < ActionDispatch::IntegrationTest
  test "commercial transaction disclosure lists only approved payment methods" do
    get legal_path

    assert_response :success
    assert_includes response.body, "クレジットカード決済、Apple Pay、Google Pay、コンビニ決済"
    assert_not_includes response.body, "PayPay"
  end
end
