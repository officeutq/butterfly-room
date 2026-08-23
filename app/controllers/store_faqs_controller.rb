# frozen_string_literal: true

require "uri"

class StoreFaqsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    @categories = StoreFaqCatalog.categories
    @return_to = safe_return_to(params[:return_to]) || stores_lp_path

    set_meta_tags(
      title: "店舗向けFAQ",
      description: "Butterflyveの店舗向けサービスに関するよくある質問をご案内します。",
      canonical: stores_faq_url,
      noindex: false,
      nofollow: false
    )
  end

  private

  def safe_return_to(value)
    candidate = value.to_s
    return if candidate.blank? || candidate.bytesize > 2_048
    return if candidate.match?(/[\\\x00-\x1f\x7f]/)
    return unless candidate.start_with?("/") && !candidate.start_with?("//")

    uri = URI.parse(candidate)
    return if uri.scheme.present? || uri.host.present? || uri.fragment.present?
    return unless allowed_return_paths.include?(uri.path)
    return if URI::DEFAULT_PARSER.unescape(candidate).match?(/[\x00-\x1f\x7f]/)

    candidate
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def allowed_return_paths
    [ stores_lp_path, stores_lp_202609_path, dashboard_path ]
  end
end
