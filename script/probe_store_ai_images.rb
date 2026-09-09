# frozen_string_literal: true

# docker compose exec -T app bin/rails runner script/probe_store_ai_images.rb '店舗名'
# Makes one paid AI request and probes only the resulting verified official URLs.
# Does not create stores, attach files, publish or retain downloaded image bytes.
abort "本番環境では実行できません" if Rails.env.production?
abort "店舗名を1つ指定してください" unless ARGV.length == 1 && ARGV.first.present?

store = Store.new(name: ARGV.first)
actor = Struct.new(:id).new(0)
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = Stores::AiAutofill::SearchService.new(
  store:, actor:, store_name: ARGV.first, image_search: true, logger: Logger.new(IO::NULL)
).call
puts({ status: result.status, model: Stores::AiAutofill::Settings.from_env.model,
       search_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
       url_candidates: result.fields.slice(*Stores::AiAutofill::ImageSources::FIELDS),
       official_sources: result.image_sources }.to_json)

result.image_sources.each do |source|
  token = Stores::AiAutofill::ImageSources.token_for([ source ], store:, actor:)
  importer = Stores::AiAutofill::ImageImportService.new(store:, actor:, token:)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  image = importer.call
  puts({ source:, found: image.present?, bytes: image&.bytes&.bytesize,
         duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
         attempts: importer.attempts }.to_json)
end
