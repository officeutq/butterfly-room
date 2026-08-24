# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# LP行動分析payloadと紐づくフォーム入力は内容全体をログへ出さない。
Rails.application.config.filter_parameters += [
  :lp_analytics_event,
  :lp_analytics_visit_id,
  :store_registration,
  :store_contact_submission,
  :store_ai_autofill
]
