namespace :logs do
  desc "古いログをアーカイブ候補として確認（errors/changes、件数上限）。APPLY=1で適用"
  task :archive, [ :kind, :limit ] => :environment do |_task, args|
    kind = { "errors" => :errors, "changes" => :changes }.fetch(args[:kind]) do
      abort "種類を指定してください: bin/rails 'logs:archive[errors,1000]'（errors または changes）"
    end
    result = Logs::ArchiveService.call(kind: kind, limit: args[:limit] || 1000, apply: ENV["APPLY"] == "1")
    puts "#{result.applied ? '適用' : '確認のみ'}: 種類=#{args[:kind]} 対象日時<#{result.cutoff.iso8601} 候補=#{result.candidate_count} アーカイブ=#{result.archived_count}"
  end
end
