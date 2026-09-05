# frozen_string_literal: true

require "base64"
require "tempfile"

module ImageUploadVerifications
  class UploadService
    class Conflict < StandardError; end
    class CapacityExceeded < StandardError; end
    class StorageError < StandardError; end

    ROLES = %w[source display].freeze
    KEY_PREFIX = "image-upload-verification/"
    URL_TTL = 5.minutes
    RUN_TTL = 15.minutes
    CLEANUP_DELAY = 1.hour
    MAX_RETAINED_RUNS = 20

    def initialize(user:)
      @user = user
    end

    def create(transport:, crop_data:)
      raise ImageValidator::Invalid, "送信方式が不正です。" unless %w[multipart direct].include?(transport)

      crop_data = ImageValidator.crop!(crop_data)
      # Serialize quota checks across requests/tabs without modifying User.
      @user.with_lock do
        if ImageUploadVerificationRun.where(user: @user).count >= MAX_RETAINED_RUNS
          raise CapacityExceeded, "検証データが20件あります。清掃後に再試行してください。"
        end
        ImageUploadVerificationRun.create!(user: @user, transport: transport, crop_data: crop_data,
          expires_at: RUN_TTL.from_now, cleanup_after: CLEANUP_DELAY.from_now)
      end
    end

    def direct_upload(id:, role:, attributes:)
      role!(role)
      run = owned_run(id)
      run.with_lock do
        pending!(run, "direct")
        raise Conflict, "この画像の送信URLは発行済みです。新しく検証を開始してください。" if run.public_send("#{role}_blob_id")

        bytes = attributes["byte_size"]
        checksum = attributes["checksum"]
        unless attributes["content_type"] == "image/jpeg" && bytes.is_a?(Integer) &&
            bytes.between?(1, ImageValidator::BYTE_LIMITS.fetch(role)) && valid_checksum?(checksum)
          raise ImageValidator::Invalid, "JPEGの容量・チェックサムが不正です。"
        end
        blob = ActiveStorage::Blob.create_before_direct_upload!(
          key: key_for(run, role), filename: "#{role}.jpg", content_type: "image/jpeg",
          byte_size: bytes, checksum: checksum, metadata: { identified: true }
        )
        run.update!("#{role}_blob" => blob)
        blob.as_json(only: %i[id filename content_type byte_size checksum]).merge(
          "signed_id" => blob.signed_id(expires_in: RUN_TTL),
          "direct_upload" => { url: blob.service_url_for_direct_upload(expires_in: URL_TTL), headers: blob.service_headers_for_direct_upload }
        )
      end
    end

    def multipart(id:, uploads:)
      run = owned_run(id)
      claim!(run, transport: "multipart", state: "uploading")
      measure(run) do
        inspected = {}
        files = ROLES.to_h do |role|
          upload = uploads[role]
          raise ImageValidator::Invalid, "編集元・表示用の2画像が必要です。" unless upload.respond_to?(:tempfile)

          inspected[role] = ImageValidator.call(upload, role: role, crop_data: run.crop_data)
          [ role, upload.tempfile ]
        end
        files.each do |role, file|
          file.rewind
          blob = ActiveStorage::Blob.build_after_unfurling(io: file, filename: "#{role}.jpg",
            key: key_for(run, role), content_type: "image/jpeg", identify: false)
          # Persist the cleanup reference BEFORE doing any external upload.
          run.with_lock do
            active!(run, "uploading")
            blob.save!
            run.update!("#{role}_blob" => blob)
          end
          file.rewind
          blob.upload_without_unfurling(file)
        end
        verify_pair(run, inspected: inspected)
      end
    end

    def complete(id:, signed_ids:)
      run = owned_run(id)
      run.with_lock do
        pending!(run, "direct")
        ROLES.each do |role|
          blob = run.public_send("#{role}_blob")
          supplied = ActiveStorage::Blob.find_signed(signed_ids[role])
          unless blob && supplied&.id == blob.id
            raise ImageValidator::Invalid, "この検証・送信者に属する2画像ではありません。"
          end
        end
        run.update!(state: "verifying")
      end
      measure(run) { verify_pair(run) }
    end

    def cancel(id:)
      run = owned_run(id)
      run.with_lock { run.update!(state: "canceled") }
      # A presigned PUT cannot be revoked; keep keys until expiry + grace.
      { state: "canceled", cleanup_after: run.cleanup_after.iso8601 }
    end

    private

    def owned_run(id)
      ImageUploadVerificationRun.where(user: @user).find(id)
    end

    def role!(role)
      raise ImageValidator::Invalid, "画像用途が不正です。" unless ROLES.include?(role)
    end

    def key_for(run, role)
      "#{KEY_PREFIX}#{run.id}/#{role}/#{SecureRandom.base58(28)}"
    end

    def valid_checksum?(value)
      value.is_a?(String) && value.length == 24 && Base64.strict_decode64(value).bytesize == 16
    rescue ArgumentError
      false
    end

    def pending!(run, transport)
      raise Conflict, "送信方式が一致しません。" unless run.transport == transport

      active!(run, "pending")
    end

    def active!(run, state)
      unless run.state == state && run.expires_at.future?
        raise Conflict, "期限切れ・処理済み・中止済みです。新しく検証を開始してください。"
      end
    end

    def claim!(run, transport:, state:)
      run.with_lock do
        pending!(run, transport)
        run.update!(state: state)
      end
    end

    def measure(run)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      images = yield
      report = { transport: run.transport, state: "complete", images: images,
        total_bytes: images.values.sum { |info| info[:bytes] },
        server_milliseconds: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1),
        cleanup_after: run.cleanup_after.iso8601, storage: run.source_blob.service.class.name,
        note: "検証時点の実体を確認。本番モデルへの添付・再編集用の永続保存ではありません。" }
      run.with_lock do
        active!(run, run.transport == "direct" ? "verifying" : "uploading")
        run.update!(state: "complete", report: report)
      end
      report
    rescue StandardError => error
      run.with_lock { run.update!(state: "failed") unless run.state == "canceled" }
      raise if error.is_a?(ImageValidator::Invalid) || error.is_a?(Conflict)

      Rails.logger.warn("[ImageUploadVerifications] upload failed run=#{run.id} error=#{error.class.name}")
      raise StorageError, "保存先への送信・実体確認に失敗しました。再試行してください。"
    end

    def verify_pair(run, inspected: {})
      ROLES.to_h do |role|
        blob = run.public_send("#{role}_blob")
        raise ImageValidator::Invalid, "2画像の送信が完了していません。" unless blob

        [ role, verify_blob(blob, role: role, crop_data: run.crop_data, inspected: inspected[role]) ]
      end
    end

    def verify_blob(blob, role:, crop_data:, inspected: nil)
      Tempfile.create([ "verification", ".jpg" ], binmode: true) do |file|
        count = 0
        digest = Digest::MD5.new
        # blob.open downloads before checking size. Bound the download while
        # streaming so a forged S3 object's size is not trusted.
        blob.download do |chunk|
          count += chunk.bytesize
          if count > blob.byte_size || count > ImageValidator::BYTE_LIMITS.fetch(role)
            raise ImageValidator::Invalid, "実ファイルが申告容量・上限を超えています。"
          end
          digest.update(chunk)
          file.write(chunk)
        end
        unless count == blob.byte_size && digest.base64digest == blob.checksum
          raise ImageValidator::Invalid, "実ファイルの容量・チェックサムが一致しません。"
        end
        file.flush
        if inspected
          # The same SHA-256 as the fully decoded multipart file proves the
          # stored bytes without decoding the same large JPEG a second time.
          raise ImageValidator::Invalid, "保存後の画像が検査済み画像と一致しません。" unless Digest::SHA256.file(file.path).hexdigest == inspected[:sha256]
          inspected
        else
          ImageValidator.call(file, role: role, crop_data: crop_data)
        end
      end
    end
  end
end
