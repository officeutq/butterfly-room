require "test_helper"

class StreamSessionTest < ActiveSupport::TestCase
  test "title length max 64" do
    s = StreamSession.new(title: "a" * 65)
    s.validate
    assert_includes s.errors[:title], "is too long (maximum is 64 characters)"
  end
end
