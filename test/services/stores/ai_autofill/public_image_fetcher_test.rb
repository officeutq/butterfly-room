# frozen_string_literal: true

require "test_helper"

class Stores::AiAutofill::PublicImageFetcherTest < ActiveSupport::TestCase
  Fetcher = Stores::AiAutofill::PublicImageFetcher
  Resolver = Struct.new(:addresses) do
    def getaddresses(host)
      addresses.fetch(host, [ "93.184.216.34" ])
    end
  end
  class Connection
    attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout, :write_timeout, :max_retries
    attr_reader :request_value

    def initialize(response)
      @response = response
    end

    def start
      yield self
    end

    def request(request)
      @request_value = request
      yield @response
      @response
    end
  end

  test "pins the public address and bounds redirects, bytes and encoded content" do
    connections = []
    queue = [ response("302", location: "https://cdn.example/photo"), response("200", chunks: [ "abc", "def" ]) ]
    fetcher = build_fetcher(queue, connections:)
    result = fetcher.call("https://shop.example/image", max_bytes: 6, deadline: deadline)
    assert_equal "abcdef", result.body
    assert_equal "https://cdn.example/photo", result.url
    assert_equal "93.184.216.34", connections.first.ipaddr
    assert_equal "identity", connections.first.request_value["Accept-Encoding"]
    assert_equal 0, connections.first.max_retries

    assert_raises(Fetcher::Error) do
      build_fetcher([ response("200", chunks: [ "123", "4567" ]) ]).call("https://shop.example", max_bytes: 6, deadline: deadline)
    end
    assert_raises(Fetcher::Error) do
      build_fetcher([ response("200", encoding: "gzip") ]).call("https://shop.example", max_bytes: 6, deadline: deadline)
    end
  end

  test "rejects private mixed or mapped DNS answers before opening a connection" do
    %w[127.0.0.1 10.0.0.1 169.254.169.254 192.168.1.1 100.64.0.1 ::1 ::ffff:127.0.0.1 fd00::1 fe80::1].each do |address|
      connections = []
      fetcher = build_fetcher([], connections:, addresses: { "shop.example" => [ "93.184.216.34", address ] })
      assert_raises(Fetcher::Error, address) do
        fetcher.call("https://shop.example", max_bytes: 100, deadline: deadline)
      end
      assert_empty connections
    end
  end

  test "validates every redirect and does not send authentication or access private destinations" do
    connections = []
    fetcher = build_fetcher([ response("302", location: "http://internal.example/") ], connections:,
      addresses: { "internal.example" => [ "169.254.169.254" ] })
    assert_raises(Fetcher::Error) { fetcher.call("https://shop.example", max_bytes: 100, deadline: deadline) }
    assert_equal 1, connections.size
    %w[file:///etc/passwd https://user:pass@shop.example https://shop.example:8080].each do |url|
      assert_raises(Fetcher::Error) { build_fetcher([]).call(url, max_bytes: 100, deadline: deadline) }
    end
    assert_raises(Fetcher::Error) do
      build_fetcher([ response("302", location: "https://shop.example/login") ]).call(
        "https://shop.example/profile", max_bytes: 100, deadline: deadline, allowed_redirect: ->(_) { false }
      )
    end
    assert_raises(Fetcher::Error) { build_fetcher([]).call("https://shop.example", max_bytes: 100, deadline: 0) }
  end

  private

  def deadline
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
  end

  def response(code, location: nil, chunks: [], encoding: nil)
    result = Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1", code, "test")
    result["location"] = location if location
    result["content-encoding"] = encoding if encoding
    result["content-type"] = "image/jpeg"
    result.define_singleton_method(:read_body) { |&block| chunks.each(&block) }
    result
  end

  def build_fetcher(queue, connections: [], addresses: {})
    Fetcher.new(resolver: Resolver.new(addresses), http_factory: lambda do |_host, _port|
      connection = Connection.new(queue.shift)
      connections << connection
      connection
    end)
  end
end
