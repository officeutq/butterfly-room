// #1340: 専用DB・代替AWS応答と実際のRails画面で切断上限〜運用復旧を検証する。
// 実IVS・カメラ・マイク・スマートフォン実機の試験ではない。
const { spawn, spawnSync, execFileSync } = require("node:child_process");
const { randomBytes, randomUUID } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { chromium, expect } = require("@playwright/test");

if (!process.argv.includes("--run")) {
  console.log("専用テストDBを作成して実行: node script/verify_publisher_retry.cjs --run");
  process.exit(0);
}
const suffix = randomBytes(4).toString("hex");
const database = `butterfly_room_retry1340_${suffix}`;
const container = `br-retry1340-${suffix}`;
const out = path.resolve("tmp", `retry1340-${suffix}`);
fs.mkdirSync(out, { recursive: true });
const base = "http://127.0.0.1:3014";
const dbUrl = `postgres://postgres:postgres@db:5432/${database}`;
const existing = spawnSync("docker", ["compose", "exec", "-T", "db", "psql", "-U", "postgres", "-d", "postgres", "-Atc",
  `SELECT 1 FROM pg_database WHERE datname = '${database}'`], { encoding: "utf8", timeout: 30000 });
assert.equal(existing.status, 0, existing.stderr);
assert.equal(existing.stdout.trim(), "", "既存の専用DBにはschemaを再投入しません");
const envArgs = Object.entries({
  RAILS_ENV: "test", DATABASE_URL: dbUrl, DATABASE_URL_TEST: dbUrl,
  ACTUAL_PUBLISHER_CONTROL_ENABLED: "true", APP_ENV: "test", APP_HOST: "127.0.0.1", APP_PORT: "3014",
  AWS_ACCESS_KEY_ID: "verification", AWS_SECRET_ACCESS_KEY: "verification", AWS_SESSION_TOKEN: "",
  AWS_PROFILE: "", AWS_EC2_METADATA_DISABLED: "true", AWS_SDK_CONFIG_OPT_OUT: "true",
}).flatMap(([key, value]) => ["-e", `${key}=${value}`]);
const created = spawnSync("docker", ["compose", "exec", "-T", ...envArgs, "app", "bundle", "exec", "rails", "db:create", "db:schema:load"], { encoding: "utf8", timeout: 180000 });
assert.equal(created.status, 0, created.stderr);

const log = fs.createWriteStream(path.join(out, "server.log"));
const child = spawn("docker", ["compose", "run", "--rm", "--no-deps", "-T", "--name", container,
  "-p", "127.0.0.1:3014:3014", ...envArgs, "app", "bundle", "exec", "rails", "runner", "script/verify_publisher_retry.rb"], { stdio: ["pipe", "pipe", "pipe"] });
let buffer = "";
let waiter;
const replies = [];
const pending = () => new Promise((resolve, reject) => {
  if (replies.length) return resolve(replies.shift());
  const timeout = setTimeout(() => { waiter = null; reject(new Error("verification runner timeout; see server.log")); }, 60000);
  waiter = { resolve: (value) => { clearTimeout(timeout); resolve(value); }, reject: (error) => { clearTimeout(timeout); reject(error); } };
});
child.stderr.on("data", (chunk) => log.write(chunk));
child.stdout.on("data", (chunk) => {
  buffer += chunk.toString();
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline);
    buffer = buffer.slice(newline + 1);
    if (line.startsWith("RETRY1340 ")) {
      const value = JSON.parse(line.slice(10));
      if (waiter) { const current = waiter; waiter = null; current.resolve(value); }
      else replies.push(value);
    } else log.write(`${line}\n`);
  }
});
child.on("exit", (code) => { if (waiter) { waiter.reject(new Error(`verification runner exited ${code}; see server.log`)); waiter = null; } });
const command = (operation, parameters = {}) => {
  const response = pending();
  child.stdin.write(`${JSON.stringify({ operation, ...parameters })}\n`);
  return response;
};
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const business = (snapshot) => ({ session: snapshot.session, orders: snapshot.orders, wallet: snapshot.wallet, transactions: snapshot.transactions, ledgers: snapshot.ledgers });
const report = { commit: execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim(), database, aws: "stub responses only", cases: [] };
let browser;
let ready;

async function login(context, user) {
  const page = await context.newPage();
  await page.goto(`${base}/users/sign_in`);
  await page.locator("#user_email").fill(user.email);
  await page.locator("#user_password").fill(ready.password);
  await page.getByRole("button", { name: "ログイン", exact: true }).click();
  await expect(page).not.toHaveURL(/\/users\/sign_in/);
  await page.close();
}
async function start(context, sessionId, generation = 0) {
  const tokenResponse = await context.request.post(`${base}/stream_sessions/${sessionId}/ivs_participant_tokens`, {
    data: { role: "publisher", request_id: randomUUID(), expected_generation: generation },
  });
  assert.equal(tokenResponse.status(), 200, await tokenResponse.text());
  const token = await tokenResponse.json();
  const identity = { request_id: token.request_id, generation: token.generation };
  const confirmed = await context.request.patch(`${base}/cast/stream_sessions/${sessionId}/start_broadcast`, { data: identity });
  assert.equal(confirmed.status(), 200, await confirmed.text());
  return identity;
}

(async () => {
  try {
    ready = await pending();
    assert(ready.ready);
    browser = await chromium.launch({ headless: true });
    report.browser = `Chromium ${browser.version()}`;
    const admin = await browser.newContext({ baseURL: base, viewport: { width: 1440, height: 1000 }, locale: "ja-JP" });
    await login(admin, ready.users.system_admin);
    await admin.request.post(`${base}/admin/current_store`, { form: { store_id: ready.store_id } });
    const adminPage = await admin.newPage();

    for (const [index, scenario] of [
      { role: "cast", failures: 1, mode: "normal" },
      { role: "store_admin", failures: 2, mode: "normal" },
      { role: "system_admin", failures: 3, mode: "normal" },
      { role: "store_admin", failures: 4, mode: "normal" },
      { role: "store_admin", failures: 4, mode: "force" },
    ].entries()) {
      const key = `case${index + 1}`;
      const fixture = await command("prepare", { key, role: scenario.role });
      const context = await browser.newContext({ baseURL: base, viewport: { width: 1440, height: 1000 }, locale: "ja-JP" });
      await login(context, ready.users[scenario.role]);
      const identity = await start(context, fixture.session_id);
      await command("drinks", { key });
      await command("failures", { count: scenario.failures });
      let ended;
      if (scenario.mode === "force") {
        ended = await admin.request.post(`${base}/admin/booths/${fixture.booth_id}/force_end`, {
          data: { stream_session_id: fixture.session_id, generation: identity.generation },
        });
      } else {
        ended = await context.request.post(`${base}/cast/stream_sessions/${fixture.session_id}/finish`, { data: identity });
      }
      assert.equal(ended.status(), 202, await ended.text());
      assert.equal((await ended.json()).disconnect_state, "retrying");
      const page = await context.newPage();
      await page.goto(`${base}/cast/stream_sessions/${fixture.session_id}`);
      const status = page.locator('[data-controller="publisher-disconnect-status"]');
      await expect(status).toContainText("再試行しています");
      await expect(status).toHaveClass(/alert-warning/);
      assert.equal(await page.getByRole("button", { name: /再確認|切断を再試行/ }).count(), 0);

      let snapshot;
      const deadline = Date.now() + 15000;
      do {
        await command("tick");
        snapshot = await command("snapshot", { key });
        if (snapshot.connections[0].released_at || snapshot.connections[0].disconnect_failed_at) break;
        await pause(100);
      } while (Date.now() < deadline);
      assert.equal(snapshot.calls.length, Math.min(4, scenario.failures + 1));
      const intervals = snapshot.calls.slice(1).map((call, i) => call.time - snapshot.calls[i].time);
      intervals.forEach((interval, i) => assert(interval >= [0.5, 1, 2][i] - 0.01, `retry too early: ${interval}`));
      assert.equal(snapshot.session.status, "ended");
      assert.equal(snapshot.session.actual_publisher_user_id, ready.users[scenario.role].id);
      assert.equal(snapshot.session.started_by_cast_user_id, fixture.creator_id);
      assert.deepEqual(snapshot.orders.map((order) => order.status), ["refunded", "refunded"]);
      assert.equal(snapshot.transactions.filter((entry) => entry.kind === "release").length, 2);
      assert.equal(snapshot.wallet.reserved_points, 0);
      assert.equal(snapshot.wallet.available_points, 10000);
      assert.equal(snapshot.ledgers.length, 0);
      const endedBusiness = business(snapshot);

      if (scenario.failures === 4) {
        assert(snapshot.connections[0].disconnect_failed_at);
        assert.equal(snapshot.errors.length, 1);
        const error = snapshot.errors[0];
        assert.equal(error.exception_class, "Ivs::DisconnectPublisherConnectionService::RetryExhausted");
        assert.equal(error.actor_user_id, ready.users[scenario.role].id);
        assert.equal(error.request_id, identity.request_id);
        assert.equal(error.source, "application");
        assert(!JSON.stringify(error).includes("verification-token"));
        await page.reload();
        await expect(status).toContainText("配信の終了と未消化ドリンクの返却は完了しました。配信接続の切断を確認できませんでした。");
        await expect(status).toHaveClass(/alert-danger/);
        await page.screenshot({ path: path.join(out, `${key}-result.png`), fullPage: true });
        await page.setViewportSize({ width: 390, height: 844 });
        await expect(status).toBeVisible();
        await page.screenshot({ path: path.join(out, `${key}-result-narrow.png`), fullPage: true });

        await adminPage.goto(`${base}/system_admin/error_logs?request_id=${identity.request_id}`);
        await adminPage.getByRole("link", { name: `ログ${error.id}の詳細`, exact: true }).click();
        await expect(adminPage.locator("body")).toContainText(identity.request_id);
        await expect(adminPage.locator("body")).toContainText(error.exception_class);
        await adminPage.screenshot({ path: path.join(out, `${key}-log.png`), fullPage: true });
        const denied = await context.request.get(`${base}/system_admin/error_logs/${error.id}`, { maxRedirects: 0 });
        assert([302, 303, 403].includes(denied.status()));
        const newTab = await context.newPage();
        await newTab.goto(`${base}/cast/stream_sessions/${fixture.session_id}`);
        await expect(newTab.locator('[data-controller="publisher-disconnect-status"]')).toHaveClass(/alert-danger/);
        await context.request.delete(`${base}/users/sign_out`);
        await login(context, ready.users[scenario.role]);
        await command("collect", { key });
        await command("tick");
        assert.equal((await command("restart", { key })).error, "publisher_disconnect_pending");
        for (const prefix of ["cast", "admin"]) {
          const oldApi = await context.request.post(`${base}/${prefix}/booths/${fixture.booth_id}/retry_publisher_disconnect`);
          assert.equal(oldApi.status(), 404);
        }
        const unchanged = await command("snapshot", { key });
        assert.equal(unchanged.calls.length, 4);
        assert.equal(unchanged.errors.length, 1);
        assert.deepEqual(business(unchanged), endedBusiness);
        const readOnly = await command("recover", { key });
        assert.equal(readOnly.applied, false);
        assert.equal(readOnly.state, "failed");
        assert.equal((await command("snapshot", { key })).calls.length, 4);
        await command("failures", { count: 0 });
        const recovered = await command("recover", { key, apply: true });
        assert.equal(recovered.state, "disconnected");
        assert.equal(recovered.attempts, 5);
        const after = await command("snapshot", { key });
        assert.deepEqual(business(after), endedBusiness);
        assert.equal(after.connections[0].disconnect_failed_at, snapshot.connections[0].disconnect_failed_at);
        await page.reload();
        await expect(status).toBeHidden();
      } else {
        assert(snapshot.connections[0].released_at);
        assert.equal(snapshot.errors.length, 0);
        await page.reload();
        await expect(status).toBeHidden();
      }
      const next = await command("restart", { key });
      const nextIdentity = await start(context, next.session_id, next.generation);
      const nextEnd = await context.request.post(`${base}/cast/stream_sessions/${next.session_id}/finish`, { data: nextIdentity });
      assert.equal(nextEnd.status(), 200, await nextEnd.text());
      assert.equal((await nextEnd.json()).disconnect_state, "disconnected");
      const final = await command("snapshot", { key });
      assert.deepEqual(business(final), endedBusiness);
      report.cases.push({ key, ...scenario, ...fixture, result: "passed", attempts: snapshot.calls.length, intervals,
        error_id: snapshot.errors[0]?.id, recovered: scenario.failures === 4, next_start_and_end: "passed" });
      console.log(`${key}: ${scenario.role} ${scenario.mode}, failures=${scenario.failures}: passed`);
      await context.close();
    }
    report.cleanup = await command("cleanup");
    assert.equal(report.cleanup.unreleased, 0);
    assert.equal(report.cleanup.live, 0);
    report.result = "passed";
  } catch (error) {
    report.result = "failed";
    report.error = error.message;
    process.exitCode = 1;
    console.error(error.message);
  } finally {
    if (ready && child.exitCode === null) {
      try { report.cleanup ??= await command("cleanup"); } catch (error) { report.cleanup_error = error.message; }
      child.stdin.end(`${JSON.stringify({ operation: "quit" })}\n`);
    }
    if (browser) await browser.close();
    spawnSync("docker", ["stop", "--time", "5", container], { encoding: "utf8" });
    report.finished_at = new Date().toISOString();
    fs.writeFileSync(path.join(out, "result.json"), `${JSON.stringify(report, null, 2)}\n`);
    log.end();
    console.log(`結果: ${path.join(out, "result.json")}`);
  }
})();
