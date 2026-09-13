// #1298 の実接続調査。既存StageやアプリDBには触れず、今回作ったStageだけを使う。
// 実行: node script/probe_ivs_realtime_connections.cjs --run
// AWS profile=default のローカル開発用認証を使用し、合成映像のみを送出する。
// トークンはメモリーだけに保持。出力・結果ファイルには保存しない。
const { execFile } = require("node:child_process")
const { promisify } = require("node:util")
const { createServer } = require("node:http")
const { writeFileSync, mkdirSync } = require("node:fs")
const { resolve } = require("node:path")
const { randomUUID } = require("node:crypto")
const { chromium } = require("playwright")

if (process.argv.length !== 3 || process.argv[2] !== "--run") {
  console.log("AWSへ一時Stageを作成する調査です。実行する場合は --run を指定してください。")
  process.exit(0)
}

const runId = `issue1298-${randomUUID()}`
const stageName = `br-local-${runId}`
const sdkUrl = "https://web-broadcast.live-video.net/1.30.0/amazon-ivs-web-broadcast.js"
const execute = promisify(execFile)
const secrets = []
const results = { runId, startedAt: new Date().toISOString(), sdk: "1.30.0", events: [] }
const resultPath = resolve("tmp", `${runId}.json`)
let stageArn, browser, server, baseUrl, lastSessionId

function redact(value) {
  let text = JSON.stringify(value)
  for (const token of secrets) text = text.split(token).join("[TOKEN]")
  return JSON.parse(text)
}

function record(name, details) {
  const event = redact({ at: new Date().toISOString(), name, ...details })
  results.events.push(event)
  writeFileSync(resultPath, JSON.stringify(results, null, 2), "utf8")
  console.log(JSON.stringify(event))
}

async function aws(service, operation, input) {
  try {
    const { stdout } = await execute("aws", [
      service, operation, "--profile", "default", "--region", "ap-northeast-1",
      "--output", "json", "--no-cli-pager", "--cli-connect-timeout", "10", "--cli-read-timeout", "20",
      ...(input ? [ "--cli-input-json", JSON.stringify(input) ] : [])
    ], { windowsHide: true, timeout: 35000, maxBuffer: 2 * 1024 * 1024 })
    return { ok: true, data: stdout.trim() ? JSON.parse(stdout) : {} }
  } catch (error) {
    const message = String(error.stderr || error.message)
    return { ok: false, error: message.match(/An error occurred \(([^)]+)\)/)?.[1] || "local_or_transport_error" }
  }
}

async function requireAws(service, operation, input) {
  const response = await aws(service, operation, input)
  if (!response.ok) throw new Error(`${operation}: ${response.error}`)
  return response.data
}

async function mint(label, duration = 3) {
  const response = await requireAws("ivs-realtime", "create-participant-token", {
    stageArn, duration, capabilities: [ "PUBLISH" ],
    attributes: { role: "publisher", stream_session_id: runId, user_id: "research-only", case: label }
  })
  const token = response.participantToken
  secrets.push(token.token)
  record(`${label}.issued`, { participantId: token.participantId, expirationTime: token.expirationTime })
  return token
}

async function disconnect(token, label) {
  const response = await aws("ivs-realtime", "disconnect-participant", {
    stageArn, participantId: token.participantId, reason: "isolated issue1298 research"
  })
  record(label, { ok: response.ok, error: response.error })
  if (!response.ok) throw new Error(`${label}: ${response.error}`)
  return response
}

async function pageState(page) {
  return page.evaluate(() => ({ ...window.probe.state, events: [...window.probe.state.events] }))
}

async function join(token, label) {
  const context = await browser.newContext()
  const page = await context.newPage()
  await page.goto(baseUrl)
  await page.addScriptTag({ url: sdkUrl })
  await page.evaluate(tokenValue => {
    const { Stage, LocalStageStream, SubscribeType, StageEvents } = window.IVSBroadcastClient
    const canvas = document.getElementById("synthetic")
    const paint = canvas.getContext("2d")
    let frame = 0
    const timer = setInterval(() => {
      paint.fillStyle = frame++ % 2 ? "#234567" : "#456789"
      paint.fillRect(0, 0, canvas.width, canvas.height)
      paint.fillStyle = "white"
      paint.fillText("Synthetic IVS probe", 10, 30)
    }, 100)
    const media = canvas.captureStream(10)
    const stream = new LocalStageStream(media.getVideoTracks()[0])
    const stage = new Stage(tokenValue, {
      stageStreamsToPublish: () => [stream],
      shouldPublishParticipant: () => true,
      shouldSubscribeToParticipant: () => SubscribeType.NONE
    })
    const state = { connection: null, publish: null, joinResult: "pending", error: null, events: [] }
    const event = (type, value) => state.events.push({ type, value, at: Date.now() })
    stage.on(StageEvents.STAGE_CONNECTION_STATE_CHANGED, value => {
      state.connection = value; event("connection", value)
    })
    stage.on(StageEvents.STAGE_PARTICIPANT_PUBLISH_STATE_CHANGED, (participant, value) => {
      if (participant.isLocal) { state.publish = value; event("publish", value) }
    })
    stage.on(StageEvents.ERROR, error => {
      state.error = { code: error.code, category: error.category }; event("error", state.error)
    })
    stage.on(StageEvents.STAGE_LEFT, value => event("left", value))
    window.probe = { stage, state, media, timer }
    stage.join().then(() => { state.joinResult = "resolved" }).catch(error => {
      state.joinResult = "rejected"
      state.error = { code: error.code, category: error.category }
    })
  }, token.token)
  let timedOut = false
  try {
    await page.waitForFunction(() => window.probe.state.publish === "published" ||
      window.probe.state.joinResult === "rejected" || window.probe.state.error, null, { timeout: 25000 })
  } catch { timedOut = true }
  record(label, { timedOut, ...await pageState(page) })
  if (timedOut) throw new Error(`${label}: observation_timeout`)
  return { page, context }
}

async function close(handle, label) {
  await handle.page.evaluate(() => {
    window.probe.stage.leave()
    window.probe.media.getTracks().forEach(track => track.stop())
    clearInterval(window.probe.timer)
  })
  record(label, await pageState(handle.page))
  await handle.context.close()
}

async function snapshot(token, label) {
  const response = await aws("ivs-realtime", "get-stage", { arn: stageArn })
  if (!response.ok) { record(label, response); return }
  lastSessionId = response.data.stage.activeSessionId || lastSessionId
  if (!lastSessionId) { record(label, { activeSessionId: null }); return }
  let nextToken, participants = []
  do {
    const result = await requireAws("ivs-realtime", "list-participants", {
      stageArn, sessionId: lastSessionId, ...(nextToken ? { nextToken } : {})
    })
    participants.push(...result.participants.map(p => ({ participantId: p.participantId, state: p.state, published: p.published })))
    nextToken = result.nextToken
  } while (nextToken)
  const detail = await aws("ivs-realtime", "get-participant", {
    stageArn, sessionId: lastSessionId, participantId: token.participantId
  })
  const participant = detail.data?.participant
  record(label, {
    activeSessionId: response.data.stage.activeSessionId || null, queriedSessionId: lastSessionId, participants,
    detail: participant ? { state: participant.state, published: participant.published, attributes: participant.attributes } : { error: detail.error }
  })
}

async function main() {
  mkdirSync(resolve("tmp"), { recursive: true })
  const identity = await requireAws("sts", "get-caller-identity")
  if (!identity.Arn.endsWith(":user/butterfly-room-local")) throw new Error("local development identity required")
  record("identity_checked", { localDevelopmentUser: true })
  server = createServer((_req, res) => {
    res.writeHead(200, { "Content-Type": "text/html", "Cache-Control": "no-store" })
    res.end('<!doctype html><meta charset="utf-8"><canvas id="synthetic" width="320" height="180"></canvas>')
  })
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve))
  baseUrl = `http://127.0.0.1:${server.address().port}`
  browser = await chromium.launch({ headless: true })
  record("browser", { version: browser.version() })
  const created = await requireAws("ivs-realtime", "create-stage", {
    name: stageName, tags: { app: "butterfly-room", env: "local-probe", issue: "1298", probe_run: runId }
  })
  stageArn = created.stage.arn
  record("stage_created", { stageArn, stageName })

  const unused = await mint("V01")
  await snapshot(unused, "V01.before_join")
  await disconnect(unused, "V01.disconnect_before_join")
  await disconnect(unused, "V01.disconnect_repeated")
  const denied = await join(unused, "V01.join_after_disconnect")
  await close(denied, "V01.cleanup")

  const connected = await mint("V02")
  const live = await join(connected, "V02.join")
  await snapshot(connected, "V02.connected_snapshot")
  await disconnect(connected, "V02.disconnect_connected")
  try { await live.page.waitForFunction(() => window.probe.state.connection === "disconnected", null, { timeout: 10000 }) } catch {}
  record("V02.after_disconnect", await pageState(live.page))
  await snapshot(connected, "V02.disconnected_snapshot")
  await close(live, "V02.cleanup")
  const reuse = await join(connected, "V02.same_token_retry")
  await close(reuse, "V02.retry_cleanup")
  await disconnect(connected, "V06.repeat_after_disconnect")

  const voluntary = await mint("V03")
  const first = await join(voluntary, "V03.first_join")
  await close(first, "V03.voluntary_leave")
  const second = await join(voluntary, "V03.same_token_after_leave")
  await snapshot(voluntary, "V03.after_rejoin_snapshot")
  await close(second, "V03.cleanup")
  await disconnect(voluntary, "V03.revoke_after_leave")

  const expiring = await mint("V04", 1)
  const persistent = await join(expiring, "V04.join_before_expiry")
  const until = new Date(expiring.expirationTime).getTime() + 2000
  while (Date.now() < until) {
    record("V04.awaiting_expiry", { remainingSeconds: Math.ceil((until - Date.now()) / 1000) })
    await new Promise(resolve => setTimeout(resolve, Math.min(10000, until - Date.now())))
  }
  record("V04.connection_after_expiry", await pageState(persistent.page))
  await snapshot(expiring, "V04.after_expiry_snapshot")
  await close(persistent, "V04.leave_after_expiry")
  const expired = await join(expiring, "V04.expired_token_retry")
  await close(expired, "V04.cleanup")
}

main().catch(error => {
  record("probe_error", { message: error.message })
  process.exitCode = 1
}).finally(async () => {
  try { if (browser) await browser.close() } catch {}
  if (stageArn) {
    try {
      const { stage } = await requireAws("ivs-realtime", "get-stage", { arn: stageArn })
      if (stage.name !== stageName || stage.tags?.probe_run !== runId || stage.tags?.env !== "local-probe") {
        throw new Error("cleanup ownership mismatch")
      }
      await requireAws("ivs-realtime", "delete-stage", { arn: stageArn })
      const after = await aws("ivs-realtime", "get-stage", { arn: stageArn })
      record("stage_cleanup", { deleted: !after.ok && after.error === "ResourceNotFoundException", result: after.error || "still_present" })
      if (after.ok || after.error !== "ResourceNotFoundException") process.exitCode = 1
    } catch (error) {
      record("cleanup_error", { stageArn, message: error.message }); process.exitCode = 1
    }
  }
  if (server) await new Promise(resolve => server.close(resolve))
  record("finished", { exitCode: process.exitCode || 0, resultPath })
})
