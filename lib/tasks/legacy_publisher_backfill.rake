# frozen_string_literal: true

module LegacyPublisherBackfillTask
  module_function

  def call(environment = ENV)
    mode = environment.fetch("PUBLISHER_BACKFILL_MODE", "plan")
    path = environment.fetch("PUBLISHER_BACKFILL_MANIFEST")
    git_commit = environment.fetch("PUBLISHER_BACKFILL_GIT_COMMIT")
    service = StreamSessions::LegacyPublisherBackfillService.new
    if mode == "plan"
      # 既存の承認対象一覧を上書きしない。
      File.open(path, "wx", encoding: "UTF-8", perm: 0o600) do |file|
        manifest = service.plan(git_commit: git_commit)
        file.write(JSON.pretty_generate(manifest))
        puts JSON.generate(event: "legacy_publisher_backfill_plan", sha256: manifest.fetch("sha256"),
          target_count: manifest.fetch("entries").size, excluded_counts: manifest.fetch("excluded_counts"))
      end
    elsif %w[apply restore].include?(mode)
      manifest = JSON.parse(File.read(path, encoding: "UTF-8"))
      result = service.run(manifest: manifest, mode: mode, git_commit: git_commit,
        confirmation: environment.fetch("PUBLISHER_BACKFILL_CONFIRM_SHA256")) do |entry|
        puts JSON.generate(event: "legacy_publisher_backfill_entry", mode: mode, manifest_sha256: manifest.fetch("sha256"), **entry)
        $stdout.flush
      end
      puts JSON.generate(event: "legacy_publisher_backfill_summary", **result)
    else
      raise ArgumentError, "PUBLISHER_BACKFILL_MODE must be plan, apply, or restore"
    end
  end
end

namespace :stream_sessions do
  desc "Plan, apply, or restore the fixed legacy publisher manifest"
  task backfill_legacy_publishers: :environment do
    LegacyPublisherBackfillTask.call
  rescue StandardError => error
    # DB例外の値や個人情報をCLIに展開しない。終了コードとクラスを残し、同じ一覧で再開する。
    abort JSON.generate(event: "legacy_publisher_backfill_failure", error_class: error.class.name)
  end
end
