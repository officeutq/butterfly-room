# frozen_string_literal: true

class StoreLpsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[show]

  def show
    set_store_lp_meta_tags
  end

  private

  def set_store_lp_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    title = "店舗向けライブ配信LP"
    description = "#{brand_name}は、夜の店が既存客向けにライブ配信を行い、ドリンク送信と消化で売上をつくる店舗向けサービスです。"

    set_meta_tags(
      title: title,
      description: description,
      noindex: false,
      nofollow: false,
      canonical: stores_lp_url,
      og: {
        title: "#{title} | #{brand_name}",
        description: description,
        type: "website",
        url: stores_lp_url,
        image: view_context.image_url("logo.png")
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end
end
