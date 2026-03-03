require "test_helper"

class StreamSessionTest < ActiveSupport::TestCase
  test "title length max 64" do
    s = StreamSession.new(title: "a" * 65)
    s.validate
    assert_includes s.errors[:title], "is too long (maximum is 64 characters)"
  end

  test "description length max 256" do
    s = StreamSession.new(description: "a" * 257)
    s.validate
    assert_includes s.errors[:description], "is too long (maximum is 256 characters)"
  end
end
