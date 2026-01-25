# frozen_string_literal: true

module Admin::MetricsHelper
  def seconds_to_hhmm(seconds)
    s = seconds.to_i
    h = s / 3600
    m = (s % 3600) / 60
    format("%d:%02d", h, m)
  end
end
