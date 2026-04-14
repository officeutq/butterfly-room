require "test_helper"

class StreamSessionTest < ActiveSupport::TestCase
  test "title length max 64" do
    s = StreamSession.new(title: "a" * 65)
    s.validate
    assert_includes s.errors.details[:title], { error: :too_long, count: 64 }
  end
end
