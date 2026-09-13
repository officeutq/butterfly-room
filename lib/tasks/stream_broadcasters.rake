namespace :stream_broadcasters do
  desc "指定旧配信のIVS参加者証拠を調査（SESSION_ID必須、DB更新なし）"
  task investigate: :environment do
    session = StreamSession.find(ENV.fetch("SESSION_ID"))
    puts JSON.pretty_generate(StreamSessions::BroadcasterEvidenceService.investigate(session))
  end

  desc "証拠補正の具体的差分を表示（PLAN必須、DB更新なし）"
  task evidence_preview: :environment do
    plan = JSON.parse(File.read(ENV.fetch("PLAN"), encoding: "UTF-8"))
    puts JSON.pretty_generate(StreamSessions::BroadcasterEvidenceService.new(plan: plan).preview)
  end

  desc "確認済みの証拠補正を適用（PLAN必須）"
  task evidence_apply: :environment do
    plan = JSON.parse(File.read(ENV.fetch("PLAN"), encoding: "UTF-8"))
    puts JSON.pretty_generate(StreamSessions::BroadcasterEvidenceService.new(plan: plan).apply)
  end

  desc "旧配信の補完計画をJSONファイルへ出力（DB更新なし、CUTOFFとOUTPUT必須）"
  task preview: :environment do
    result = StreamSessions::LegacyBroadcasterBackfill.preview(cutoff: ENV.fetch("CUTOFF"))
    File.write(ENV.fetch("OUTPUT"), JSON.pretty_generate(result), mode: "wx", encoding: "UTF-8")
    puts JSON.generate(result.fetch("counts"))
  end

  desc "確認済み計画の旧配信者補完を適用（PLAN必須）"
  task apply: :environment do
    manifest = JSON.parse(File.read(ENV.fetch("PLAN"), encoding: "UTF-8"))
    puts JSON.pretty_generate(StreamSessions::LegacyBroadcasterBackfill.new(manifest: manifest).apply)
  end

  desc "計画に一致する補完だけを取り消す（後の証拠補正は保持、PLAN必須）"
  task rollback: :environment do
    manifest = JSON.parse(File.read(ENV.fetch("PLAN"), encoding: "UTF-8"))
    puts JSON.pretty_generate(StreamSessions::LegacyBroadcasterBackfill.new(manifest: manifest).rollback)
  end
end
