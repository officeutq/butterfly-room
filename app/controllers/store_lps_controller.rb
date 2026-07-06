# frozen_string_literal: true

class StoreLpsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[show show_202607]
  layout "store_lp_202607", only: %i[show_202607]

  def show
    set_store_lp_meta_tags
  end

  def show_202607
    set_store_lp_202607_meta_tags
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

  def set_store_lp_202607_meta_tags
    brand_name = "Butterflyve（バタフライブ）"
    title = "夜のお店のための新しい遠隔配信ツール"
    description = "#{brand_name}は、夜のお店が既存客向けに遠隔配信を行い、ドリンク送信と消化で売上をつくる店舗向けサービスです。"

    set_meta_tags(
      title: title,
      description: description,
      noindex: true,
      nofollow: false,
      canonical: stores_lp_202607_url,
      og: {
        title: "#{title} | #{brand_name}",
        description: description,
        type: "website",
        url: stores_lp_202607_url,
        image: view_context.image_url("store_lp_202607/logo/01.png")
      },
      twitter: {
        card: "summary_large_image"
      }
    )
  end
end
