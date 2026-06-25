# frozen_string_literal: true

class SupportInquiryMailer < ApplicationMailer
  def received
    @support_inquiry = params[:support_inquiry]
    @support_inquiry_message = params[:support_inquiry_message]

    mail(
      to: @support_inquiry.reply_email,
      subject: "【Butterflyve】お問い合わせを受け付けました"
    )
  end

  def reply
    @support_inquiry = params[:support_inquiry]
    @support_inquiry_message = params[:support_inquiry_message]

    mail(
      to: @support_inquiry.reply_email,
      subject: "【Butterflyve】お問い合わせに返信がありました"
    )
  end
end
