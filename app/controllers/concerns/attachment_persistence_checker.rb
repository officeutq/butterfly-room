# frozen_string_literal: true

module AttachmentPersistenceChecker
  extend ActiveSupport::Concern

  private

  def ensure_attachment_persisted!(record:, attachment_name:)
    attachment = record.public_send(attachment_name)
    return true unless attachment.attached?

    # test環境ではスキップ
    return true if Rails.env.test?

    blob = attachment.blob

    unless blob.service.exist?(blob.key)
      Rails.logger.error(
        "[AttachmentPersistence] missing blob " \
        "record=#{record.class.name}##{record.id} " \
        "attachment=#{attachment_name} blob_id=#{blob.id} key=#{blob.key}"
      )

      attachment.purge
      record.errors.add(attachment_name, "の保存に失敗しました。再度アップロードしてください")

      return false
    end

    true
  end
end
