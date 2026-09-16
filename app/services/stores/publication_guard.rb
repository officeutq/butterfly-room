module Stores
  # 店舗更新と配信準備・開始を直列化する。必ずブースのロックより先に取得する。
  # 複数ブースの配信処理同士は共有ロックで並行できる。
  module PublicationGuard
    MESSAGE = "非公開店舗のブースでは配信準備・配信開始はできません。店舗を公開してから操作してください".freeze

    def self.with_lock(booth:)
      Store.transaction do
        Store.lock("FOR SHARE").find(booth.store_id)
        yield
      end
    end

    def self.ensure_published!(booth:)
      return if Store.uncached { Store.published.where(id: booth.store_id).exists? }

      raise StreamSessions::PublisherControl::Error.new(code: "store_unpublished", message: MESSAGE, booth: booth)
    end
  end
end
