const {spawn, spawnSync} = require('node:child_process');
const {randomBytes} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require('@playwright/test');
const suffix = randomBytes(4).toString('hex');
const database = `butterfly_room_booth1294_${suffix}`;
const container = `br-booth1294-${suffix}`;
const out = path.resolve('tmp', `booth1294-${suffix}`);
fs.mkdirSync(out, {recursive:true});
const dbUrl = `postgres://postgres:postgres@db:5432/${database}`;
const existing = spawnSync('docker', ['compose','exec','-T','db','psql','-U','postgres','-d','postgres','-Atc', `SELECT 1 FROM pg_database WHERE datname = '${database}'`], {encoding:'utf8',timeout:30000});
assert.equal(existing.status,0,existing.stderr);
assert.equal(existing.stdout.trim(),'');
const env = {RAILS_ENV:'test', DATABASE_URL:dbUrl, DATABASE_URL_TEST:dbUrl, APP_ENV:'test', APP_HOST:'127.0.0.1',APP_PORT:'3015',ACTUAL_PUBLISHER_CONTROL_ENABLED:'true',AWS_ACCESS_KEY_ID:'verification',AWS_SECRET_ACCESS_KEY:'verification',AWS_PROFILE:'',AWS_SESSION_TOKEN:'',AWS_EC2_METADATA_DISABLED:'true',AWS_SDK_CONFIG_OPT_OUT:'true'};
const envArgs=Object.entries(env).flatMap(([k,v])=>['-e',`${k}=${v}`]);
const created = spawnSync('docker',['compose','exec','-T',...envArgs,'app','bundle','exec','rails','db:create','db:schema:load'],{encoding:'utf8',timeout:180000});
assert.equal(created.status,0,created.stderr);
const log=fs.createWriteStream(path.join(out,'server.log'));
// 開発サーバーと共有するPIDファイルを削除する既定entrypointを使わない。
const child=spawn('docker',['compose','run','--rm','--no-deps','-T','--entrypoint','bundle','--name',container,'-p','127.0.0.1:3015:3015',...envArgs,'app','exec','rails','runner','tests/manual_capture/booth_management_fixture.rb']);
let buffer='', waiter, failure, replies=[];
function reply() {
  return new Promise((resolve,reject)=>{
    if(replies.length) return resolve(replies.shift());
    if(failure) return reject(failure);
    const timer=setTimeout(()=>{waiter=null;reject(Error(`Capture timed out; see ${path.join(out,'server.log')}`));},60000);
    waiter={
      resolve(value){clearTimeout(timer);waiter=null;resolve(value);},
      reject(error){clearTimeout(timer);waiter=null;reject(error);}
    };
  });
}
child.on('error',error=>{failure=error;waiter?.reject(error);});
child.on('close',code=>{
  failure=Error(`Capture server exited (${code}); see ${path.join(out,'server.log')}`);
  waiter?.reject(failure);
});
child.stderr.on('data',d=>log.write(d));
child.stdout.on('data',d=>{buffer+=d.toString();let i;while((i=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,i);buffer=buffer.slice(i+1);if(line.startsWith('PREVIEW1294 ')){const v=JSON.parse(line.slice(12));if(waiter)waiter.resolve(v);else replies.push(v);}else log.write(line+'\n');}});
let browser;
(async()=>{
  try {
    const ready=await reply();
    browser=await chromium.launch({headless:true});
    const report = await require('./booth_management_flow.cjs').run(browser, ready, out);
    child.stdin.write('quit\n');
    const unchanged=await reply();
    assert.equal(unchanged.records_unchanged,true);
    report.protectedRecordsUnchanged=true;
    report.stubbedDisconnects=unchanged.stubbed_disconnects;
    report.forceEndAndClose=unchanged.force_end_and_close;
    fs.writeFileSync(path.join(out,'result.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify({out,...report}));
  } finally {
    await browser?.close();
    spawnSync('docker',['stop','-t','2',container],{encoding:'utf8',timeout:15000});
    log.end();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
