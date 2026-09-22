const { spawn, spawnSync } = require("node:child_process")
const { randomBytes } = require("node:crypto")
const fs = require("node:fs")
const path = require("node:path")
const assert = require("node:assert/strict")
const { chromium, expect } = require("@playwright/test")

const suffix = randomBytes(4).toString("hex")
const database = `butterfly_room_members1359_${suffix}`
const container = `br-members1359-${suffix}`
const out = path.resolve("tmp", `members1359-${suffix}`)
fs.mkdirSync(out, { recursive: true })
const dbUrl = `postgres://postgres:postgres@db:5432/${database}`
const env = { RAILS_ENV: "test", DATABASE_URL: dbUrl, DATABASE_URL_TEST: dbUrl, APP_ENV: "test",
  APP_HOST: "127.0.0.1", APP_PORT: "3016", ACTUAL_PUBLISHER_CONTROL_ENABLED: "false",
  AWS_ACCESS_KEY_ID: "verification", AWS_SECRET_ACCESS_KEY: "verification", AWS_PROFILE: "", AWS_SESSION_TOKEN: "",
  AWS_EC2_METADATA_DISABLED: "true", AWS_SDK_CONFIG_OPT_OUT: "true" }
const envArgs = Object.entries(env).flatMap(([k, v]) => ["-e", `${k}=${v}`])
const created = spawnSync("docker", ["compose", "exec", "-T", ...envArgs, "app", "bundle", "exec", "rails", "db:create", "db:schema:load"], { encoding: "utf8", timeout: 180000 })
assert.equal(created.status, 0, created.stderr)
const log = fs.createWriteStream(path.join(out, "server.log"))
const child = spawn("docker", ["compose", "run", "--rm", "--no-deps", "-T", "--entrypoint", "bundle", "--name", container,
  "-p", "127.0.0.1:3016:3016", ...envArgs, "app", "exec", "rails", "runner", "tests/manual_capture/store_members_invitations_fixture.rb"])
let buffer = "", waiter, failure, replies = []
function reply() {
  return new Promise((resolve, reject) => {
    if (replies.length) return resolve(replies.shift())
    if (failure) return reject(failure)
    const timer = setTimeout(() => { waiter = null; reject(Error(`Timed out: ${out}`)) }, 60000)
    waiter = { resolve(value) { clearTimeout(timer); waiter = null; resolve(value) }, reject(error) { clearTimeout(timer); waiter = null; reject(error) } }
  })
}
child.on("error", error => { failure = error; waiter?.reject(error) })
child.on("close", code => { failure = Error(`Server exited (${code}): ${out}`); waiter?.reject(failure) })
child.stderr.on("data", data => log.write(data))
child.stdout.on("data", data => {
  buffer += data.toString()
  let i
  while ((i = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, i); buffer = buffer.slice(i + 1)
    if (line.startsWith("MEMBERS1359 ")) {
      const value = JSON.parse(line.slice(12))
      if (waiter) waiter.resolve(value); else replies.push(value)
    } else log.write(line + "\n")
  }
})
let browser
;(async () => {
  try {
    const ready = await reply()
    browser = await chromium.launch({ headless: true })
    const report = []
    for (const scenario of ready.scenarios) {
      const context = await browser.newContext({ viewport: { width: scenario.width, height: 960 } })
      await context.addInitScript(href => {
        const loadIcons = () => {
          if (document.querySelector("link[data-capture-icons]")) return
          const link = document.createElement("link")
          link.rel = "stylesheet"; link.href = href; link.dataset.captureIcons = "true"
          document.head.appendChild(link)
        }
        document.addEventListener("DOMContentLoaded", loadIcons)
        document.addEventListener("turbo:load", loadIcons)
      }, ready.icon_stylesheet)
      // 端末への実送信はせず、ブラウザへ渡す共有本文とコピー内容を検証する。
      await context.addInitScript(() => {
        window.sharedPayloads = []; window.copiedUrls = []
        Object.defineProperty(navigator, "share", { configurable: true, value: undefined })
        Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: async text => window.copiedUrls.push(text) } })
      })
      const page = await context.newPage()
      const errors = []
      page.on("pageerror", error => errors.push(error.message))
      const turboClick = async locator => {
        const loaded = page.evaluate(() => new Promise(resolve => document.addEventListener("turbo:load", () => resolve(true), { once: true })))
        await locator.click()
        await loaded
      }
      await page.goto("http://127.0.0.1:3016/users/sign_in")
      await page.locator("#user_email").fill(scenario.email)
      await page.locator("#user_password").fill(ready.password)
      await page.locator("form#new_user input[type=submit], form#new_user button[type=submit]").click()
      await page.waitForURL(url => !url.pathname.includes("sign_in"))
      await page.evaluate(async storeId => {
        const response = await fetch("/admin/current_store", { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" }, body: JSON.stringify({ store_id: storeId }) })
        if (!response.ok) throw Error("Store selection failed")
      }, scenario.store_id)
      await page.goto("http://127.0.0.1:3016/admin/casts")
      await expect(page.locator("[data-membership-role=admin]")).toContainText("確認用店舗管理者")
      await expect(page.locator("[data-membership-role=admin] form")).toHaveCount(0)
      await expect(page.locator("[data-membership-role=cast]")).toContainText("確認用キャスト")
      await page.screenshot({ path: path.join(out, `${scenario.role}-${scenario.width}-members.png`), fullPage: true })

      for (const kind of ["admin", "cast"]) {
        await turboClick(page.getByRole("link", { name: kind === "admin" ? "管理者招待一覧" : "キャスト招待一覧", exact: true }))
        const button = page.getByRole("link", { name: kind === "admin" ? "店舗管理者招待URLを発行" : "キャスト招待URLを発行", exact: true })
        await button.click()
        const modal = page.locator(".modal.show")
        await expect(modal.getByRole("button", { name: "招待URLをコピー", exact: true })).toBeEnabled()
        const note = `${kind}-${scenario.role}-${scenario.width} 確認メモ`
        await modal.getByLabel("管理者用メモ（任意）").fill(note)
        const url = await modal.locator("input[readonly]").inputValue()
        await modal.getByRole("button", { name: "招待URLをコピー", exact: true }).click()
        await expect(modal.getByRole("button", { name: "閉じる", exact: true }).last()).toBeEnabled()
        await modal.getByLabel("管理者用メモ（任意）").fill(note + " 保存")
        await page.screenshot({ path: path.join(out, `${scenario.role}-${scenario.width}-${kind}-modal.png`), fullPage: true })
        await modal.getByRole("button", { name: "閉じる", exact: true }).last().click()
        await expect(page.locator("#modal .modal")).toHaveCount(0)
        await expect(page.locator("#store_invitation_list")).toContainText(note + " 保存")
        assert.ok((await page.evaluate(() => window.copiedUrls)).includes(url))
        await expect(button).toBeFocused()
        if (kind === "admin") {
          await button.click()
          await expect(modal.getByRole("button", { name: "招待URLをコピー", exact: true })).toBeEnabled()
          await modal.getByLabel("管理者用メモ（任意）").fill("取消されるメモ")
          await modal.getByRole("button", { name: "キャンセル", exact: true }).click()
          await expect(page.locator("#modal .modal")).toHaveCount(0)
          await expect(page.locator("#store_invitation_list")).not.toContainText("取消されるメモ")
          await expect(page.locator("#store_invitation_list .referral-code-card")).toHaveCount(1)
        }
        await page.screenshot({ path: path.join(out, `${scenario.role}-${scenario.width}-${kind}-list.png`), fullPage: true })
      }
      assert.deepEqual(errors, [])
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, "horizontal overflow")
      report.push({ ...scenario, email: undefined, checked: "所属・両招待発行・メモ保存・コピー・一覧反映・管理者取消・フォーカス復帰" })
      await context.close()
    }
    child.stdin.write("quit\n")
    const records = await reply()
    assert.equal(records.admin_shared, 4)
    assert.equal(records.admin_cancelled, 4)
    assert.equal(records.cast_shared, 4)
    fs.writeFileSync(path.join(out, "result.json"), JSON.stringify({ report, records }, null, 2))
    console.log(JSON.stringify({ out, report, records }))
  } finally {
    await browser?.close()
    spawnSync("docker", ["stop", "-t", "2", container], { encoding: "utf8", timeout: 15000 })
    log.end()
  }
})().catch(error => { console.error(error); process.exitCode = 1 })
