// verify_publisher_retry.cjs 専用。Rails画面と配信制御JSはそのまま使用し、
// 外部SDK・加工映像だけを代替する。実カメラ／IVS送信の確認には数えない。
const assert = require("node:assert/strict");
const path = require("node:path");
const { expect } = require("@playwright/test");

function installStage() {
  window.verificationStages = [];
  class Stage {
    constructor(_token, strategy) {
      this.strategy = strategy;
      this.events = new Map();
      this.leaves = 0;
      window.verificationStages.push(this);
    }
    on(name, fn) { if (!this.events.has(name)) this.events.set(name, new Set()); this.events.get(name).add(fn); }
    off(name, fn) { this.events.get(name)?.delete(fn); }
    emit(name, ...args) { for (const fn of [...(this.events.get(name) || [])]) fn(...args); }
    async join() { this.emit("publish", { isLocal: true }, "published"); }
    leave() { this.leaves++; this.emit("left"); }
    refreshStrategy() {}
  }
  window.IVSBroadcastClient = {
    Stage, LocalStageStream: class { constructor(track) { this.track = track; } setMuted(muted) { this.track.enabled = !muted; } },
    SubscribeType: { NONE: "none" },
    StageEvents: { STAGE_CONNECTION_STATE_CHANGED: "connection", STAGE_PARTICIPANT_PUBLISH_STATE_CHANGED: "publish", STAGE_LEFT: "left" },
    StageParticipantPublishState: { PUBLISHED: "published" },
  };
}

const provider = `export class BanubaProvider {
  constructor(ctx) { this.ctx = ctx; }
  async start() {
    if (this.canvas) return;
    this.canvas = document.createElement("canvas");
    this.canvas.width = 640; this.canvas.height = 360;
    const paint = this.canvas.getContext("2d");
    paint.fillStyle = "#234"; paint.fillRect(0, 0, 640, 360);
    paint.fillStyle = "white"; paint.font = "24px sans-serif";
    paint.fillText("Synthetic verification video", 30, 170);
    this.ctx.banubaSurfaceTarget.append(this.canvas);
  }
  async ensurePublishTrack() {
    if (!this.ctx._banubaVideoTrack) {
      this.ctx._banubaStream = this.canvas.captureStream(10);
      this.ctx._banubaVideoTrack = this.ctx._banubaStream.getVideoTracks()[0];
    }
    this.ctx._banubaStageStream ||= new window.IVSBroadcastClient.LocalStageStream(this.videoTrack);
  }
  async stop() { this.canvas?.remove(); this.canvas = null; }
  async ensureInitialBeautyStateLoaded() {}
  async applyEffect() {}
  async updateBeauty() {}
  get videoTrack() { return this.ctx._banubaVideoTrack; }
  get stageStream() { return this.ctx._banubaStageStream; }
}`;

function assertSameRequest(requests, expected) {
  assert.equal(requests.length, expected);
  assert.equal(new Set(requests.map((request) => JSON.stringify(request.identity))).size, 1);
  const intervals = requests.slice(1).map((request, index) => (request.time - requests[index].time) / 1000);
  intervals.forEach((interval, index) => assert(interval >= [0.5, 1, 2][index] - 0.02, `early retry: ${interval}`));
  return intervals;
}

module.exports = async function verifyBrowser({ browser, base, command, login, ready, out, report }) {
  report.browser_cases = [];
  for (const role of ["cast", "store_admin", "system_admin"]) {
    for (const width of [1440, 390]) {
      const context = await browser.newContext({ baseURL: base, viewport: { width, height: 844 }, locale: "ja-JP", permissions: ["microphone"] });
      await context.addInitScript(installStage);
      await context.route("https://web-broadcast.live-video.net/**", (route) => route.fulfill({ contentType: "application/javascript", body: "/* test SDK installed by init script */" }));
      await context.route(/\/assets\/controllers\/ivs_publisher\/beauty_providers\/banuba_provider[^/]*\.js$/, (route) => route.fulfill({ contentType: "application/javascript", body: provider }));
      await login(context, ready.users[role]);

      async function prepare(key) {
        const fixture = await command("prepare", { key, role });
        const selected = await context.request.post(`${base}/cast/current_booth`, { form: { booth_id: fixture.booth_id } });
        assert(selected.ok());
        const page = await context.newPage();
        await page.goto(`${base}/cast/booths/${fixture.booth_id}/live`);
        await page.waitForFunction(() => window.publisher?._previewOnly && window.publisher._beautyProvider.videoTrack?.readyState === "live");
        return { page, fixture };
      }
      async function endNormally(page, fixture) {
        await page.locator('[data-ivs-publisher-target="endBtn"]').click();
        await expect(page).toHaveURL(`${base}/cast/stream_sessions/${fixture.session_id}`, { timeout: 15000 });
        await page.close();
      }
      for (const failures of [0, 1, 2, 3, 4]) {
        const key = `start-${role}-${width}-${failures}`;
        const { page, fixture } = await prepare(key);
        let fail = true;
        const confirmations = [];
        const requests = [];
        page.on("request", (request) => {
          const url = new URL(request.url());
          if (url.pathname.startsWith("/cast/stream_sessions/") || url.pathname.endsWith("/ivs_participant_tokens")) requests.push(url.pathname);
        });
        await page.route(`**/cast/stream_sessions/${fixture.session_id}/start_broadcast`, async (route) => {
          confirmations.push({ identity: route.request().postDataJSON(), time: Date.now() });
          if (fail && confirmations.length <= failures) {
            await route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ error: "publisher_state_unavailable", message: "配信状態を確認できません。再確認してください" }) });
          } else await route.continue();
        });
        await page.locator('[data-ivs-publisher-target="startBtn"]').click();
        await page.waitForFunction(() => window.publisher && !window.publisher._publisherStartOperation &&
          (window.publisher._broadcasting || window.publisher._state === "error"), null, { timeout: 20000 });
        const intervals = assertSameRequest(confirmations, Math.min(failures + 1, 4));
        let snapshot = await command("snapshot", { key });
        assert.equal(snapshot.connections.length, 1);
        assert.equal(requests.filter((url) => url.endsWith("/ivs_participant_tokens")).length, 1);
        const error = page.locator('[data-ivs-publisher-target="errorMessage"]');
        if (failures === 4) {
          assert.equal(snapshot.session.actual_publisher_user_id, null);
          assert.equal(snapshot.session.broadcast_started_at, null);
          assert.equal(snapshot.booth_status, "standby");
          assert(snapshot.connections[0].released_at);
          assert.equal(snapshot.errors.length, 1);
          assert.equal(snapshot.errors[0].exception_class, "StreamSessions::ReportPublisherConfirmationFailureService::RetryExhausted");
          assert.equal(snapshot.errors[0].request_id, confirmations[0].identity.request_id);
          assert.equal(snapshot.errors[0].actor_user_id, ready.users[role].id);
          assert(!JSON.stringify(snapshot.errors).includes("verification-token"));
          assert.equal(requests.filter((url) => url.endsWith("/cancel_broadcast")).length, 1);
          await expect(error).toHaveText("配信状態を確認できません。再確認してください");
          await expect(page.getByRole("button", { name: "再確認", exact: true })).toHaveCount(0);
          assert(await page.evaluate(() => window.verificationStages.every((stage) => stage.leaves > 0) && !window.publisher._audioTrack && !window.publisher._beautyProvider.videoTrack));
          await page.screenshot({ path: path.join(out, `${key}.png`) });
          fail = false;
          await page.locator('[data-ivs-publisher-target="startBtn"]').click();
          await page.waitForFunction(() => window.publisher?._broadcasting && !window.publisher._publisherStartOperation);
          snapshot = await command("snapshot", { key });
          assert.equal(snapshot.connections.length, 2);
          assert.equal(snapshot.errors.length, 1);
        } else {
          assert.equal(snapshot.errors.length, 0);
          await expect(page.locator('[data-ivs-publisher-target="error"]')).toBeHidden();
        }
        assert.equal(snapshot.session.actual_publisher_user_id, ready.users[role].id);
        assert.equal(snapshot.booth_status, "live");
        await endNormally(page, fixture);
        report.browser_cases.push({ key, role, width, failures, confirmation_attempts: Math.min(failures + 1, 4), intervals, result: "passed" });
        console.log(`${key}: passed`);
      }

      for (const committed of [false, true]) {
        const key = `end-unknown-${role}-${width}-${committed}`;
        const { page, fixture } = await prepare(key);
        await page.locator('[data-ivs-publisher-target="startBtn"]').click();
        await page.waitForFunction(() => window.publisher?._broadcasting && !window.publisher._publisherStartOperation);
        await command("drinks", { key });
        const endings = [];
        await page.route(`**/cast/stream_sessions/${fixture.session_id}/finish`, async (route) => {
          endings.push({ identity: route.request().postDataJSON(), time: Date.now() });
          if (committed && endings.length === 1) {
            const result = await route.fetch();
            assert.equal(result.status(), 200);
          }
          await route.abort("failed");
        });
        await page.locator('[data-ivs-publisher-target="endBtn"]').click();
        await expect(page.locator('[data-ivs-publisher-target="errorMessage"]')).toHaveText("配信の終了結果を確認できませんでした。時間をおいて画面を読み込み直してください。", { timeout: 15000 });
        const intervals = assertSameRequest(endings, 4);
        await expect(page).toHaveURL(`${base}/cast/booths/${fixture.booth_id}/live`);
        await expect(page.locator('[data-ivs-publisher-target="startBtn"]')).toBeDisabled();
        assert(await page.evaluate(() => window.verificationStages.every((stage) => stage.leaves > 0) && !window.publisher._audioTrack && !window.publisher._beautyProvider.videoTrack));
        await page.evaluate(() => window.publisher.endBroadcast());
        assert.equal(endings.length, 4);
        const snapshot = await command("snapshot", { key });
        assert.equal(snapshot.session.status, committed ? "ended" : "live");
        assert.equal(snapshot.session.actual_publisher_user_id, ready.users[role].id);
        assert.deepEqual(snapshot.orders.map((order) => order.status), committed ? ["refunded", "refunded"] : ["pending", "pending"]);
        await page.screenshot({ path: path.join(out, `${key}.png`) });
        await page.close();
        await command("cleanup");
        const after = await command("snapshot", { key });
        assert.equal(after.transactions.filter((entry) => entry.kind === "release").length, 2);
        assert.equal(after.wallet.available_points, 10000);
        assert.equal(after.wallet.reserved_points, 0);
        assert.equal(after.session.actual_publisher_user_id, ready.users[role].id);
        report.browser_cases.push({ key, role, width, committed, finish_attempts: 4, intervals, result: "passed" });
        console.log(`${key}: passed`);
      }
      await context.close();
    }
  }
};
