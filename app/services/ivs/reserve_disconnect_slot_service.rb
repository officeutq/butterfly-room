module Ivs
  # 同じDBのapp/worker全体で、同じAWSアカウント・リージョンへの切断を毎秒4件に抑える。
  # AWSの毎秒5件枠には他環境・運用操作も含まれるため、429も通常の失敗として有限回扱う。
  class ReserveDisconnectSlotService
    INTERVAL = 0.25.seconds

    def self.call(stage_arn:)
      key = stage_arn.split(":")[3..4].join(":")
      limit = IvsDisconnectLimit.create_or_find_by!(id: key) { |row| row.next_available_at = Time.current }
      limit.with_lock do
        now = Time.current
        return limit.next_available_at if limit.next_available_at > now

        limit.update!(next_available_at: now + INTERVAL)
        nil
      end
    end
  end
end
