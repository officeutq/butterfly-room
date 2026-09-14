// #1298 の調査用権限を使い、#1301・#1302 の実装と実IVSを接続する。実行: node script/probe_actual_publisher.cjs --run
// test DBの専用データ、一時Stage、合成映像・音声のみ。トークンはパイプとメモリー以外へ出さない。
const { spawn, execFile } = require("node:child_process")
const { promisify } = require("node:util")
const { createInterface } = require("node:readline")
const { createServer } = require("node:http")
const { readFileSync, writeFileSync } = require("node:fs")
const { randomUUID } = require("node:crypto")
const { chromium } = require("playwright")
const assert = require("node:assert/strict")

if (process.argv.length !== 3 || process.argv[2] !== "--run") {
  console.log("一時Stageとtest DBを使用する調査です。実行時は --run を指定してください。")
  process.exit(0)
}
const execute = promisify(execFile)
const runId = `issue1298-${randomUUID()}`
const stageName = `br-local-${runId}`
const resultPath = `tmp/issue1302-${runId}.json`
const events = []
let stageArn, worker, browser, server, baseUrl
const pending = []
function record(name, details) {
  const event = { at: new Date().toISOString(), name, ...details }
  events.push(event)
  writeFileSync(resultPath, JSON.stringify({ runId, events }, null, 2), "utf8")
  console.log(JSON.stringify(event))
}
async function aws(operation, input) {
  try {
    const { stdout } = await execute("aws", ["ivs-realtime", operation, "--profile", "default", "--region", "ap-northeast-1",
      "--output", "json", "--no-cli-pager", "--cli-connect-timeout", "10", "--cli-read-timeout", "20", "--cli-input-json", JSON.stringify(input)],
    { windowsHide: true, timeout: 35000 })
    return stdout.trim() ? JSON.parse(stdout) : {}
  } catch (error) {
    throw new Error(`${operation}: ${String(error.stderr).match(/An error occurred \(([^)]+)\)/)?.[1] || "transport_error"}`)
  }
}
function command(input) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("rails_probe_timeout")), 90000)
    pending.push(result => { clearTimeout(timer); resolve(result) })
    worker.stdin.write(`${JSON.stringify(input)}\n`)
  })
}

async function main() {
  const created = await aws("create-stage", { name: stageName,
    tags: { app: "butterfly-room", env: "local-probe", issue: "1298", probe_run: runId, implementation: "1302" } })
  stageArn = created.stage.arn
  record("stage_created", { stageArn })
  worker = spawn("docker", ["compose", "exec", "-T", "-e", "RAILS_ENV=test", "-e", "ACTUAL_PUBLISHER_CONTROL_ENABLED=true", "app",
    "bin/rails", "runner", "script/probe_actual_publisher.rb"], { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] })
  createInterface({ input: worker.stdout }).on("line", line => {
    if (line.startsWith("BR_PROBE ")) pending.shift()?.(JSON.parse(line.slice(9)))
  })
  worker.stderr.on("data", () => {}) // DB例外等をトークン応答と混ぜて出力しない。
  worker.on("exit", code => { while (pending.length) pending.shift()({ status: 500, body: { error: `worker_exit_${code}` } }) })
  const ready = await command({ run_id: runId, stage_arn: stageArn })
  assert.equal(ready.body.ready, true, ready.body.error)
  record("test_data_ready", ready.body)
  server = createServer(async (request, response) => {
    const url = new URL(request.url, baseUrl)
    if (url.pathname === "/") {
      response.setHeader("Content-Type", "text/html")
      return response.end(`<!doctype html><meta charset="utf-8"><meta name="csrf-token" content="${runId}"><canvas id="synthetic" width="640" height="360"></canvas>`)
    }
    if (["/api_client.js", "/publisher_connection.js"].includes(url.pathname)) {
      response.setHeader("Content-Type", "application/javascript")
      const source = readFileSync(`app/javascript/controllers/ivs_publisher${url.pathname}`, "utf8")
        .replace('"controllers/ivs_publisher/api_client"', '"/api_client.js"')
      return response.end(source)
    }
    if (request.headers["x-csrf-token"] !== runId) { response.writeHead(403); return response.end() }
    try {
      let body = ""
      for await (const chunk of request) body += chunk
      const params = body ? JSON.parse(body) : Object.fromEntries(url.searchParams)
      const result = await command({ ...params, operation: url.pathname.slice(1) })
      response.writeHead(result.status, { "Content-Type": "application/json" })
      response.end(JSON.stringify(result.body))
    } catch (_) { response.writeHead(500); response.end() }
  })
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
  baseUrl = `http://127.0.0.1:${server.address().port}`
  browser = await chromium.launch({ headless: true, args: ["--autoplay-policy=no-user-gesture-required"] })
  const page = await browser.newPage()
  await page.goto(baseUrl)
  await page.addScriptTag({ url: "https://web-broadcast.live-video.net/1.30.0/amazon-ivs-web-broadcast.js" })
  await page.evaluate(async () => {
    const { PublisherConnection } = await import("/publisher_connection.js")
    const ctx = { publisherGenerationValue: 0, tokenUrlValue: "/token", publisherStateUrlValue: "/state",
      startBroadcastUrlValue: "/confirm", cancelBroadcastUrlValue: "/cancel", statusUrlValue: "/status" }
    const attempt = new PublisherConnection(ctx)
    ctx._publisherAttempt = attempt
    const token = await attempt.token()
    const sdk = window.IVSBroadcastClient
    const canvas = document.getElementById("synthetic")
    const paint = canvas.getContext("2d")
    let frame = 0
    const timer = setInterval(() => { paint.fillStyle = frame++ % 2 ? "#246" : "#468"; paint.fillRect(0, 0, 640, 360) }, 100)
    const video = canvas.captureStream(10)
    const audio = new AudioContext()
    const oscillator = audio.createOscillator(), output = audio.createMediaStreamDestination()
    oscillator.connect(output); oscillator.start(); await audio.resume()
    const streams = [video.getVideoTracks()[0], output.stream.getAudioTracks()[0]].map(track => new sdk.LocalStageStream(track))
    window.probe = { attempt, ctx, publishEnabled: false, timer, video, audio, oscillator, oldLeft: false }
    const stage = new sdk.Stage(token, { stageStreamsToPublish: () => streams,
      shouldPublishParticipant: () => window.probe.publishEnabled, shouldSubscribeToParticipant: () => sdk.SubscribeType.NONE })
    stage.on(sdk.StageEvents.STAGE_LEFT, () => { window.probe.oldLeft = true })
    window.probe.published = attempt.watchPublish(stage, sdk)
    attempt.joinPromise = stage.join()
    await attempt.joinPromise
  })
  const before = await command({ operation: "snapshot" })
  assert.equal(before.body.publisher_id, null)
  assert.equal(before.body.broadcast_started_at, null)
  assert.equal(before.body.booth_status, "standby")
  record("joined_without_publishing", before.body)
  const premature = await page.evaluate(async () => {
    const attempt = window.probe.attempt
    const response = await fetch("/confirm", { method: "POST", headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
      body: JSON.stringify({ request_id: attempt.requestId, generation: attempt.generation }) })
    return { status: response.status, body: await response.json() }
  })
  assert.equal(premature.status, 503)
  record("premature_confirmation_rejected", premature)
  const confirmed = await page.evaluate(async () => {
    const { attempt } = window.probe
    window.probe.publishEnabled = true
    attempt.stage.refreshStrategy()
    let timer
    try {
      await Promise.race([window.probe.published, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("publish_observation_timeout")), 25000) })])
    } finally { clearTimeout(timer) }
    const publishedAt = Date.now()
    try {
      await attempt.confirm()
      return { ok: true, elapsedMs: Date.now() - publishedAt, result: attempt.result }
    } catch (error) { return { ok: false, elapsedMs: Date.now() - publishedAt, error: error.code || error.message } }
  })
  record("published_confirmation", confirmed)
  assert.equal(confirmed.ok, true)
  assert.equal(confirmed.result.actual_publisher_user_id, ready.body.publisher_id)
  assert.equal(confirmed.result.booth_status, "live")
  const repeated = await page.evaluate(async () => {
    await window.probe.attempt.confirm()
    return window.probe.attempt.result
  })
  assert.deepEqual(repeated, confirmed.result)
  const after = await command({ operation: "snapshot" })
  assert.equal(after.body.creator_id, ready.body.creator_id)
  assert.equal(after.body.connections, 1)
  assert.equal(after.body.source, "ivs_verified")
  assert.equal(after.body.confirmed_at, after.body.broadcast_started_at)
  record("saved_once", after.body)
  const reconnected = await page.evaluate(async () => {
    const { PublisherConnection } = await import("/publisher_connection.js")
    const { changePublisherStatus } = await import("/api_client.js")
    const { attempt: previous, ctx } = window.probe
    ctx.streamSessionIdValue = previous.result.stream_session_id
    await changePublisherStatus(ctx, previous, "away")
    ctx.publisherGenerationValue = previous.currentGeneration
    const next = new PublisherConnection(ctx)
    ctx._publisherAttempt = next
    const beganAt = Date.now()
    const token = await next.token()
    const sdk = window.IVSBroadcastClient
    // 既存の合成映像・音声を新しいStageへ送る。
    const output = window.probe.audio.createMediaStreamDestination()
    window.probe.oscillator.connect(output)
    const streams = [window.probe.video.getVideoTracks()[0], output.stream.getAudioTracks()[0]].map(track => new sdk.LocalStageStream(track))
    const stage = new sdk.Stage(token, { stageStreamsToPublish: () => streams, shouldPublishParticipant: () => true,
      shouldSubscribeToParticipant: () => sdk.SubscribeType.NONE })
    const published = next.watchPublish(stage, sdk)
    next.joinPromise = stage.join()
    await next.joinPromise
    let timer
    try {
      await Promise.race([published, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("reconnect_observation_timeout")), 25000) })])
    } finally { clearTimeout(timer) }
    await next.confirm()
    window.probe.attempt = next
    return { elapsedMs: Date.now() - beganAt, oldRequestId: previous.requestId, newRequestId: next.requestId,
      oldLeft: window.probe.oldLeft, result: next.result }
  })
  record("reconnected", reconnected)
  assert.equal(reconnected.oldLeft, true)
  assert.notEqual(reconnected.oldRequestId, reconnected.newRequestId)
  assert.equal(reconnected.result.actual_publisher_user_id, ready.body.publisher_id)
  assert.equal(reconnected.result.broadcast_started_at, confirmed.result.broadcast_started_at)
  assert.equal(reconnected.result.stream_session_id, confirmed.result.stream_session_id)
  assert.equal(reconnected.result.generation, 2)
  const recut = await command({ operation: "repeat_old_disconnect", request_id: reconnected.oldRequestId })
  assert.equal(recut.status, 200)
  record("old_id_disconnected_again", recut.body)
  const external = await command({ operation: "external" })
  assert.equal(external.status, 200)
  assert.equal(external.body.participants.length, 1)
  assert.equal(external.body.participants[0].state, "CONNECTED")
  assert.equal(external.body.participants[0].published, true)
  assert.notEqual(external.body.participants[0].participant_id, recut.body.disconnected_participant_id)
  record("replacement_survives_old_disconnect", external.body)
}

main().catch(error => { record("probe_error", { message: error.message }); process.exitCode = 1 }).finally(async () => {
  if (browser) await browser.close()
  if (stageArn) {
    try {
      const { stage } = await aws("get-stage", { arn: stageArn })
      assert.equal(stage.name, stageName); assert.equal(stage.tags.probe_run, runId)
      await aws("delete-stage", { arn: stageArn })
      let deleted = false
      try { await aws("get-stage", { arn: stageArn }) } catch (error) { deleted = error.message.includes("ResourceNotFoundException") }
      record("stage_cleanup", { deleted }); assert.equal(deleted, true)
    } catch (error) { record("cleanup_error", { message: error.message }); process.exitCode = 1 }
  }
  if (worker && worker.exitCode === null) {
    const result = await command({ operation: "quit" })
    record("test_data_cleanup", result.body)
    worker.stdin.end()
    if (!result.body.test_data_removed) process.exitCode = 1
  }
  if (server) await new Promise(resolve => server.close(resolve))
  record("finished", { exitCode: process.exitCode || 0, resultPath })
})
