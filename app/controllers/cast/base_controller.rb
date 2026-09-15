# frozen_string_literal: true

module Cast
  class BaseController < ApplicationController
    include PublisherEntryErrors

    before_action -> { require_at_least!(:cast) }
    after_action :store_cast_return_to

    helper_method :current_booth

    private

    # cast領域の「直前ページ」をsessionに保存（Issue #304）
    #
    # - GET / HEAD の HTML のみ対象
    # - 200 OK のときだけ保存
    # - /cast/booths（選択画面）と /cast/current_booth（選択POST）では保存しない
    # - 保存値は /cast/ で始まる相対パスのみ
    def store_cast_return_to
      return unless request.get? || request.head?
      return unless request.format.html?
      return unless response.status == 200
      return unless request.fullpath.start_with?("/cast/")

      # 選択画面 / 選択POST では保存しない
      return if request.path == "/cast/booths"
      return if request.path == "/cast/current_booth"

      fullpath = request.fullpath.to_s

      # open redirect / 不正URL対策：/cast/ で始まり、// を含まないものだけ
      return unless fullpath.start_with?("/cast/")
      return if fullpath.start_with?("//")
      return if fullpath.include?("\n") || fullpath.include?("\r")
      return if fullpath.include?("\0")

      session[:cast_return_to] = fullpath
    end
  end
end
