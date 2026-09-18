const {expect} = require('@playwright/test');
const assert = require('node:assert/strict');
const path = require('node:path');

async function run(browser, ready, out) {
  const report = {browser: browser.version(), cases: []};
  for (const item of ready.scenarios) {
    const context = await browser.newContext({baseURL: 'http://127.0.0.1:3015', viewport: {width: item.width, height: item.width === 1440 ? 1400 : 1000}, locale: 'ja-JP'});
    // testレイアウトでは省略される既存Bootstrap Iconsだけを撮影用に読み込む。
    await context.addInitScript(href => {
      const loadIcons = () => {
        if (document.querySelector('link[data-capture-icons]')) return;
        const link = document.createElement('link');
        link.rel = 'stylesheet'; link.href = href; link.dataset.captureIcons = 'true';
        document.head.appendChild(link);
      };
      document.addEventListener('DOMContentLoaded', loadIcons);
      document.addEventListener('turbo:load', loadIcons);
    }, ready.icon_stylesheet);
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const turboClick = async locator => {
      // URLだけではTurboの一時的なキャッシュ表示と最終描画を区別できない。
      const loaded = page.evaluate(() => new Promise(resolve => document.addEventListener('turbo:load', () => resolve(true), {once: true})));
      await locator.click();
      await loaded;
    };
    const shot = async name => {
      await page.waitForFunction(() => [...document.styleSheets].some(sheet => sheet.ownerNode.dataset?.captureIcons === 'true'));
      await page.evaluate(() => document.fonts.ready);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'horizontal overflow');
      await page.screenshot({path: path.join(out, `${item.role}-${item.width}-${name}.png`), fullPage: true, animations: 'disabled'});
    };
    const choose = async (id, capture = false) => {
      await page.locator('header [data-bs-toggle=dropdown]').click();
      await page.locator('header a[href*="/cast/booths/select_modal"]').click();
      const modal = page.locator('#modal .modal.show');
      await expect(modal).toBeVisible();
      await expect(modal.getByRole('button', {name: /強制終了|閉鎖|再確認/})).toHaveCount(0);
      if (capture) await shot('selection');
      const form = modal.locator('form').filter({has: page.locator(`input[name=booth_id][value="${id}"]`)});
      await form.getByRole('button', {name: /切り替え|切替/}).click();
      await expect(modal).toHaveCount(0);
    };
    await page.goto('/users/sign_in');
    await page.locator('#user_email').fill(item.email);
    await page.locator('#user_password').fill(ready.password);
    await page.getByRole('button', {name: 'ログイン', exact: true}).click();
    await expect(page).not.toHaveURL(/users\/sign_in/);
    await page.goto('/dashboard');
    await choose(item.booth, true);
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', {name: /^(ブース管理|ブース一覧)$/})).toHaveCount(0);
    const createCard = page.getByRole('link').filter({has: page.getByRole('heading', {name: 'ブース新規作成', exact: true})});
    await expect(createCard).toHaveCount(item.role === 'cast' ? 0 : 1);
    await shot('dashboard');
    if (item.role !== 'cast') {
      await turboClick(createCard);
      await expect(page).toHaveURL(/\/admin\/booths\/new$/);
      await expect(page.locator('.booth-form__readonly-value')).toHaveText(item.store);
      await shot('new');
      await turboClick(page.locator('.booth-form__back'));
      await expect(page).toHaveURL(/\/dashboard$/);
    }
    await turboClick(page.getByRole('link').filter({has: page.getByRole('heading', {name: 'ブース情報', exact: true})}));
    await expect(page).toHaveURL(new RegExp(`/cast/booths/${item.booth}$`));
    await shot('information');
    if (item.role !== 'cast') {
      let confirmation = '';
      page.once('dialog', async dialog => {confirmation = dialog.message(); await dialog.dismiss();});
      await page.getByRole('button', {name: '強制終了', exact: true}).click();
      await expect(page.getByRole('button', {name: '強制終了', exact: true})).toBeVisible();
      assert.ok(confirmation.includes(item.store));
      assert.match(confirmation, /メインブース.*本日の配信.*未消化ドリンク/);
      page.once('dialog', dialog => dialog.accept());
      await turboClick(page.getByRole('button', {name: '強制終了', exact: true}));
      await expect(page.getByRole('button', {name: '閉鎖', exact: true})).toBeVisible();
      await expect(page).toHaveURL(new RegExp(`/cast/booths/${item.booth}$`));
      await shot('ended');
      page.once('dialog', dialog => dialog.accept());
      await turboClick(page.getByRole('button', {name: '閉鎖', exact: true}));
      await expect(page.locator('.booth-show .badge').filter({hasText: '閉鎖済み'})).toBeVisible();
      await shot('closed');
      await turboClick(page.getByRole('link', {name: '配信履歴', exact: true}));
      await expect(page.locator('main')).toContainText('本日の配信');
      await shot('history');
      await turboClick(page.getByRole('link', {name: 'ブース情報へ戻る', exact: true}));
      await expect(page).toHaveURL(new RegExp(`/cast/booths/${item.booth}$`));
    } else {
      await expect(page.locator('.booth-management-actions')).toHaveCount(0);
    }
    for (const target of item.closed) {
      if (item.role === 'cast') await page.goto(`/cast/booths/${target.booth}`);
      else await choose(target.booth);
      await expect(page).toHaveURL(new RegExp(`/cast/booths/${target.booth}$`));
      await expect(page.locator('.booth-show-actions a')).toHaveCount(1);
      await expect(page.locator('.booth-show-actions button, .booth-management-actions')).toHaveCount(0);
      if (item.role !== 'cast' && target.state === 'retrying') {
        await expect(page.locator('[data-controller=publisher-disconnect-status]')).toHaveAttribute('data-publisher-disconnect-status-state-value', 'retrying');
        await shot('retrying');
        await expect(page.locator('[data-controller=publisher-disconnect-status]')).toContainText('画面を読み込み直して', {timeout: 15000});
        await shot('unconfirmed');
      } else {
        await shot(target.state);
      }
      await turboClick(page.getByRole('link', {name: '配信履歴', exact: true}));
      await turboClick(page.getByRole('link', {name: 'ブース情報へ戻る', exact: true}));
      await expect(page).toHaveURL(new RegExp(`/cast/booths/${target.booth}$`));
    }
    await page.goto('/cast/booths');
    await expect(page).toHaveURL(/\/dashboard$/);
    if (item.role !== 'cast') {
      await page.goto('/admin/booths?archived=1');
      await expect(page).toHaveURL(/\/dashboard$/);
      await expect(page.locator(`[href="/cast/booths/${item.closed.at(-1).booth}"] .card-title`)).toHaveText('ブース情報');
    }
    assert.deepEqual(errors, []);
    report.cases.push({role: item.role, width: item.width, forceEndAndClose: item.role !== 'cast', closedStates: 3, historyReturn: true, oldListRedirect: true, noOverflow: true});
    await context.close();
  }
  return report;
}
module.exports = {run};
