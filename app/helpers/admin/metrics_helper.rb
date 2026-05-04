# frozen_string_literal: true

module Admin::MetricsHelper
  def seconds_to_human_time(seconds)
    s = seconds.to_i
    return "0分" if s <= 0
    return "1分未満" if s < 60

    h = s / 3600
    m = (s % 3600) / 60

    if h.positive?
      "#{h}時間#{m}分"
    else
      "#{m}分"
    end
  end
end
