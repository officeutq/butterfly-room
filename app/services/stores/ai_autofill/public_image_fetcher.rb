# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "resolv"
require "timeout"
require "uri"

module Stores
  module AiAutofill
    class PublicImageFetcher
      class Error < StandardError; end
      Result = Data.define(:body, :content_type, :url)
      BLOCKED_NETWORKS = %w[
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
        172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15
        198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
        ::/96 ::ffff:0:0/96 64:ff9b::/96 64:ff9b:1::/48 100::/64
        2001::/23 2001:db8::/32 2002::/16 fc00::/7 fe80::/10 ff00::/8
      ].map { |network| IPAddr.new(network) }.freeze

      def initialize(resolver: Resolv, http_factory: ->(host, port) { Net::HTTP.new(host, port, nil) })
        @resolver = resolver
        @http_factory = http_factory
      end

      def call(url, max_bytes:, deadline:, allowed_redirect: nil)
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Error, "timeout" unless remaining.positive?

        Timeout.timeout(remaining, Error, "timeout") do
          3.times do
            uri = public_uri!(url)
            addresses = @resolver.getaddresses(uri.hostname)
            raise Error, "non_public_address" if addresses.empty? || addresses.any? { |address| !public_address?(address) }

            response, body = request(uri, addresses.first, max_bytes:)
            if response.is_a?(Net::HTTPRedirection)
              redirected = URI.join(uri.to_s, response["location"].to_s).to_s
              raise Error, "redirect_scope" if allowed_redirect && !allowed_redirect.call(redirected)

              url = redirected
              next
            end
            raise Error, "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)
            raise Error, "encoded_response" unless [ nil, "identity" ].include?(response["content-encoding"])

            return Result.new(body:, content_type: response.content_type, url: uri.to_s)
          end
          raise Error, "too_many_redirects"
        end
      rescue URI::Error, SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError,
             Resolv::ResolvError, Net::HTTPBadResponse, Net::ProtocolError, ArgumentError => error
        raise Error, error.class.name
      end

      private

      def public_uri!(value)
        uri = URI.parse(value.to_s)
        unless %w[http https].include?(uri.scheme) && uri.hostname.present? && uri.userinfo.nil? &&
            uri.port == (uri.scheme == "https" ? 443 : 80)
          raise Error, "invalid_url"
        end
        uri.fragment = nil
        uri
      end

      def public_address?(address)
        ip = IPAddr.new(address)
        return false if ip.ipv6? && !IPAddr.new("2000::/3").include?(ip)

        BLOCKED_NETWORKS.none? { |network| network.include?(ip) }
      rescue IPAddr::InvalidAddressError
        false
      end

      def request(uri, address, max_bytes:)
        http = @http_factory.call(uri.hostname, uri.port)
        # Pin the validated DNS answer; retain the hostname for TLS/SNI and Host.
        http.ipaddr = address
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 2
        http.read_timeout = 2
        http.write_timeout = 2
        http.max_retries = 0
        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = "Butterflyve-StoreImage/1.0"
        request["Accept-Encoding"] = "identity"
        body = +"".b
        response = http.start do |connection|
          connection.request(request) do |incoming|
            next if incoming.is_a?(Net::HTTPRedirection)
            raise Error, "too_large" if incoming.content_length.to_i > max_bytes

            incoming.read_body do |chunk|
              raise Error, "too_large" if body.bytesize + chunk.bytesize > max_bytes

              body << chunk
            end
          end
        end
        [ response, body ]
      end
    end
  end
end
