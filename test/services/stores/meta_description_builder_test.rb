# frozen_string_literal: true

require "test_helper"

module Stores
  class MetaDescriptionBuilderTest < ActiveSupport::TestCase
    test "builds a description from all registered store details" do
      store = Store.new(
        name: "〇〇",
        area: "福岡・中洲",
        business_type: :girls_bar,
        business_hours: "20:00〜翌1:00",
        description: "初めての方も楽しめる明るい店舗です。",
        address: "福岡県福岡市博多区1-2-3"
      )

      assert_equal(
        "〇〇は福岡・中洲のガールズバーです。営業時間は20:00〜翌1:00。" \
          "初めての方も楽しめる明るい店舗です。Butterflyveで店舗情報と公開中のブースを確認できます。",
        MetaDescriptionBuilder.call(store)
      )
      refute_includes MetaDescriptionBuilder.call(store), store.address
    end

    test "uses only area and the Japanese business type label when other details are blank" do
      store = Store.new(name: "〇〇", area: "福岡・中洲", business_type: :girls_bar)

      assert_equal(
        "〇〇は福岡・中洲のガールズバーです。Butterflyveで店舗情報と公開中のブースを確認できます。",
        MetaDescriptionBuilder.call(store)
      )
      refute_includes MetaDescriptionBuilder.call(store), "営業時間"
    end

    test "builds a store-specific description without a store description" do
      store = Store.new(name: "〇〇", area: "渋谷", business_hours: "19:00〜24:00")

      assert_equal(
        "〇〇は渋谷の店舗です。営業時間は19:00〜24:00。Butterflyveで店舗情報と公開中のブースを確認できます。",
        MetaDescriptionBuilder.call(store)
      )
    end

    test "uses the fixed fallback when only the store name is registered" do
      store = Store.new(name: "〇〇")

      assert_equal(
        "〇〇の店舗情報と公開中のブースをButterflyve（バタフライブ）で確認できます。",
        MetaDescriptionBuilder.call(store)
      )
    end

    test "normalizes line breaks and consecutive whitespace in the store description" do
      store = Store.new(name: "〇〇", description: "明るい店舗です。\n  初めての方も  歓迎します。")

      assert_equal(
        "〇〇の店舗情報です。明るい店舗です。 初めての方も 歓迎します。" \
          "Butterflyveで店舗情報と公開中のブースを確認できます。",
        MetaDescriptionBuilder.call(store)
      )
    end

    test "limits the final description to 160 characters" do
      store = Store.new(name: "〇〇", description: "長い店舗説明" * 100)

      description = MetaDescriptionBuilder.call(store)

      assert_equal MetaDescriptionBuilder::MAX_LENGTH, description.length
      assert description.end_with?("…")
    end
  end
end
