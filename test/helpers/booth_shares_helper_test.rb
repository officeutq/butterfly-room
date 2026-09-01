# frozen_string_literal: true

require "test_helper"
require "uri"

class BoothSharesHelperTest < ActionView::TestCase
  test "x_share_intent_url encodes the text and nested share URL" do
    share_text = "蝶子の配信はここから！遊びに来てね🦋"
    share_url = "https://example.com/booths/12?stream=34"

    uri = URI.parse(x_share_intent_url(text: share_text, url: share_url))
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "https", uri.scheme
    assert_equal "x.com", uri.host
    assert_equal "/intent/tweet", uri.path
    assert_equal share_text, params["text"]
    assert_equal share_url, params["url"]
  end

  test "line_share_url encodes the text and nested share URL" do
    share_text = "蝶子のブースはこちら🦋"
    share_url = "https://example.com/booths/12?stream=34"

    uri = URI.parse(line_share_url(text: share_text, url: share_url))
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "https", uri.scheme
    assert_equal "social-plugins.line.me", uri.host
    assert_equal "/lineit/share", uri.path
    assert_equal share_text, params["text"]
    assert_equal share_url, params["url"]
  end
end
