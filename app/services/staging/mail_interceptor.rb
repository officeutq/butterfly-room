# frozen_string_literal: true

module Staging
  class MailInterceptor
    ORIGINAL_RECIPIENT_HEADERS = {
      to: "X-Staging-Original-To",
      cc: "X-Staging-Original-Cc",
      bcc: "X-Staging-Original-Bcc"
    }.freeze

    def self.delivering_email(message)
      new.delivering_email(message)
    end

    def initialize(env: ENV)
      @env = env
    end

    def delivering_email(message)
      return unless Runtime.staging?(@env)

      prefix_subject(message)

      unless Runtime.enabled?("MAIL_DELIVERY_ENABLED", default: true, env: @env)
        message.perform_deliveries = false
        return
      end

      case value("MAIL_DELIVERY_MODE")
      when "redirect"
        redirect_message(message)
      when "allowlist"
        restrict_to_allowlist(message)
      else
        message.perform_deliveries = false
      end
    end

    private

    def redirect_message(message)
      record_original_recipients(message)
      message.to = csv_values("MAIL_REDIRECT_RECIPIENT")
      message.cc = nil
      message.bcc = nil
      message.perform_deliveries = false if message.to.blank?
    end

    def restrict_to_allowlist(message)
      allowed = csv_values("MAIL_ALLOWED_RECIPIENTS").map(&:downcase)
      record_original_recipients(message)

      message.to = allowed_recipients(message.to, allowed)
      message.cc = allowed_recipients(message.cc, allowed)
      message.bcc = allowed_recipients(message.bcc, allowed)
      message.perform_deliveries = false if (Array(message.to) + Array(message.cc) + Array(message.bcc)).empty?
    end

    def record_original_recipients(message)
      ORIGINAL_RECIPIENT_HEADERS.each do |field, header|
        recipients = Array(message.public_send(field)).join(", ")
        message.header[header] = recipients if recipients.present?
      end
    end

    def allowed_recipients(recipients, allowed)
      Array(recipients).select { |recipient| allowed.include?(recipient.downcase) }
    end

    def prefix_subject(message)
      prefix = value("MAIL_SUBJECT_PREFIX")
      return if prefix.empty? || message.subject.to_s.start_with?(prefix)

      message.subject = "#{prefix} #{message.subject}".strip
    end

    def csv_values(name)
      value(name).split(",").map(&:strip).reject(&:empty?)
    end

    def value(name)
      @env[name].to_s.strip
    end
  end
end
