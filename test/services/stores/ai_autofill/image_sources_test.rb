# frozen_string_literal: true

require "test_helper"

class Stores::AiAutofill::ImageSourcesTest < ActiveSupport::TestCase
  Sources = Stores::AiAutofill::ImageSources
  Identity = Data.define(:id)

  test "orders accepted URL fields without requiring another set of official evidence" do
    fields = {
      "website_url" => "https://shop.example/branches/akihabara",
      "x_url" => "https://x.com/shop",
      "instagram_url" => "https://www.instagram.com/shop/",
      "tiktok_url" => "https://www.tiktok.com/@shop",
      "youtube_url" => "https://www.youtube.com/@shop"
    }
    result = Sources.from(fields: fields.to_a.reverse.to_h)
    assert_equal Sources::FIELDS, result.pluck("kind")
    assert_equal fields.values, result.pluck("url")

    fields["website_url"] = nil
    fields["youtube_url"] = nil
    assert_equal %w[x_url instagram_url tiktok_url], Sources.from(fields:).pluck("kind")
  end

  test "does not widen a branch URL or treat login and shared social domains as a store" do
    assert_not Sources.same_owner?("https://shop.example/a", "https://shop.example/b", field: "website_url")
    assert_not Sources.same_owner?("https://shop.example/a", "https://shop.example/ab", field: "website_url")
    assert_not Sources.same_owner?("https://x.com/shop", "https://x.com/shop", field: "website_url")
    assert_not Sources.same_owner?("https://instagram.com/accounts/login", "https://instagram.com/accounts/login", field: "instagram_url")
    assert Sources.same_owner?("https://twitter.com/shop", "https://x.com/shop/status/1", field: "x_url")
    assert_not Sources.same_owner?("https://youtube.com/watch?v=a", "https://youtube.com/watch?v=b", field: "youtube_url")
  end

  test "signed sources expire and cannot be forged or reused by another store or user" do
    store = Identity.new(id: 1)
    actor = Identity.new(id: 2)
    sources = [ { "kind" => "website_url", "url" => "https://shop.example" } ]
    token = Sources.token_for(sources, store:, actor:)
    assert_equal sources, Sources.verify(token, store:, actor:)
    assert_nil Sources.verify(token + "tampered", store:, actor:)
    assert_nil Sources.verify(token, store: Identity.new(id: 3), actor:)
    assert_nil Sources.verify(token, store:, actor: Identity.new(id: 4))
    travel 6.minutes do
      assert_nil Sources.verify(token, store:, actor:)
    end
  end
end
