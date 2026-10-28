// Run: NODE_PATH=<directory containing playwright> node tests/web/browser_test.cjs
// Prerequisites: web engine build; dart compile js tests/web/probe.dart -o build/browser-tests/probe.dart.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const {execFileSync} = require('node:child_process');
const {chromium} = require('playwright');
// Wall-clock measurements differ between independent native and Wasm runs.
// Compare every semantic/counter/event field while excluding timing telemetry.
const semanticReport = raw => JSON.parse(raw, (key,value) =>
  key === 'timings_us' || key === 'trace_us' ? undefined : value);
const root = path.resolve(__dirname,'../..');
const small = fs.readFileSync(path.join(root,'datasets/pipeline/teaching.json'),'utf8');
const large = fs.readFileSync(path.join(root,'datasets/allocation/standard-14.json'),'utf8');
const fortress = fs.readFileSync(path.join(root,'datasets/pipeline/irregular-fortress.json'),'utf8');
const cli = path.join(root,'build/windows-release/bin/dungeon_cli.exe');
const mime = {'.js':'text/javascript','.wasm':'application/wasm','.html':'text/html','.json':'application/json'};
const server = http.createServer((req,res) => {
  let name;
  try { name = decodeURIComponent(new URL(req.url,'http://localhost').pathname); } catch { res.writeHead(400).end(); return; }
  // Test subdirectory deployment as well as root deployment.
  if (name.startsWith('/nested/')) name = name.slice(7);
  if (name.startsWith('/missing/')) { res.writeHead(404).end(); return; }
  if (name === '/favicon.ico') { res.writeHead(204).end(); return; }
  let file;
  if (name === '/' || name === '/index.html') file = path.join(__dirname,'harness.html');
  else if (name === '/probe.dart.js') file = path.join(root,'build/browser-tests/probe.dart.js');
  else if (name.startsWith('/engine/')) file = path.resolve(root,'apps/flutter_ui/web',`.${name}`);
  if (!file || !file.startsWith(root+path.sep) || name.includes('..')) { res.writeHead(404).end(); return; }
  fs.readFile(file,(err,data) => { if(err) res.writeHead(404).end(); else res.writeHead(200,{'Content-Type':mime[path.extname(file)] || 'application/octet-stream','Cache-Control':'no-store'}).end(data); });
});
(async () => {
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({channel:'chrome',headless:true});
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror',e => errors.push(e.message));
    page.on('console',m => { if(m.type()==='error') console.error('browser:',m.text()); });
    await page.goto(origin);
    await page.waitForFunction(() => typeof runDartProbe === 'function');
    await page.evaluate(async () => { globalThis.client = new DungeonEngineClient(); await client.ready; });
    let checks = 0;
    for (const [operation,command] of ['validate','generate','route','optimize','run'].entries()) {
      const actual = await page.evaluate(async ({small,operation}) => client.run(small,operation+1),{small,operation});
      const expected = execFileSync(cli,[command,path.join(root,'datasets/pipeline/teaching.json'),'--json'],{encoding:'utf8',windowsHide:true});
      // The legacy validate command uses Windows text-mode CRLF stdout.
      assert.deepEqual(semanticReport(actual),semanticReport(expected),`${command} CLI/Wasm parity`); checks++;
    }
    const native = execFileSync(cli,['run',path.join(root,'datasets/pipeline/irregular-fortress.json'),'--json','--events','16'],{encoding:'utf8',windowsHide:true,maxBuffer:10*1024*1024});
    const web = await page.evaluate(fortress => client.run(fortress,5,16),fortress);
    assert.deepEqual(semanticReport(web),semanticReport(native),'150x150 irregular/14-pack parity'); checks++;
    const details = await page.evaluate(async () => {
      const metrics = JSON.parse(await client.metrics());
      let cursor = 0, events = [], batch;
      do { batch = JSON.parse(await client.trace(cursor,7)); events.push(...batch.events); cursor = batch.next_cursor; } while(cursor < batch.total);
      const doc = JSON.parse(client.lastResult), marker = doc.result.geometry.entrance_marker;
      const step = JSON.parse(await client.step(client.snapshotJob,marker.x,marker.y,1,0));
      return {metrics,events,batch,step,floor:doc.result.geometry.layers.floor};
    });
    assert.ok(details.metrics.allocation); assert.ok(details.events.length > 0 && details.events.length <= 48);
    details.events.forEach((e,i) => assert.equal(e.sequence,i));
    assert.ok(details.batch.truncated); assert.equal(details.floor[details.step.y][details.step.x],'1'); checks += 4;
    for (const malformed of ['{','{}',small+'\0',small.replace('"schema_version": 1','"schema_version": 999')]) {
      const result = await page.evaluate(async source => {
        const before = client.lastResult, report = JSON.parse(await client.run(source));
        return {report,preserved:before === client.lastResult};
      },malformed);
      assert.notEqual(result.report.outcome,'success'); assert.ok(result.preserved); checks++;
    }
    const unsupported = JSON.parse(large); unsupported.source.packs.push({...unsupported.source.packs[0],id:'extra-pack'});
    const unsupportedResult = JSON.parse(await page.evaluate(source => client.run(source),JSON.stringify(unsupported)));
    assert.equal(unsupportedResult.outcome,'unsupported_size'); assert.equal(unsupportedResult.optimal,false); checks++;
    const exhausted = JSON.parse(small); exhausted.source.settings.max_work_units = 1;
    assert.notEqual(JSON.parse(await page.evaluate(source => client.run(source),JSON.stringify(exhausted))).outcome,'success'); checks++;
    const largeInteger = JSON.parse(small); largeInteger.source.settings.threat_budget = 'BIG_INTEGER';
    const exactSource = JSON.stringify(largeInteger).replace('"BIG_INTEGER"','9007199254740993');
    const exact = await page.evaluate(async source => {
      const raw = await client.run(source);
      return {raw,decoded:JSON.parse(DungeonEngineClient.safeJson(raw))};
    },exactSource);
    assert.ok(exact.raw.includes('9007199254740993'));
    assert.equal(exact.decoded.result.source_project.source.settings.threat_budget,'9007199254740993'); checks++;
    const cancel = await page.evaluate(async large => {
      const previous = client.lastResult;
      let ticks = 0; const timer = setInterval(() => ticks++,2);
      const result = client.run(large);
      let busy = '';
      try { await client.run(large); } catch(error) { busy = error.code; }
      const start = performance.now();
      while (JSON.parse(client.progressJson).state !== 1 && performance.now()-start < 5000) await new Promise(r => setTimeout(r,5));
      await client.cancel();
      const report = JSON.parse(await result); clearInterval(timer);
      return {report,busy,ticks,preserved:client.lastResult === previous};
    },large);
    assert.equal(cancel.report.outcome,'cancelled'); assert.equal(cancel.busy,'busy'); assert.ok(cancel.ticks > 0); assert.ok(cancel.preserved); checks+=4;
    assert.equal(JSON.parse(await page.evaluate(small => client.run(small),small)).outcome,'success'); checks++;
    const dart = JSON.parse(await page.evaluate(({small,large}) => runDartProbe(small,large),{small,large}));
    assert.ok(dart.checks >= 10); checks += dart.checks;
    await page.evaluate(async large => {
      const running = client.run(large).catch(() => null);
      await new Promise(r => setTimeout(r,25)); await client.close(); await running;
      if (!client.closed || client.pending.size) throw new Error('Client not cleaned up');
    },large); checks++;
    for(let i=0;i<8;i++) {
      await page.evaluate(async source => { const c = new DungeonEngineClient(); try { await c.ready; await c.run(source,1); } finally { await c.close(); } },small); checks++;
    }
    const mismatch = await page.evaluate(async () => {
      const c = new DungeonEngineClient({abi:99}); try { await c.ready; return 'accepted'; } catch(e) {return e.code;} finally {await c.close();}
    });
    assert.equal(mismatch,'version_mismatch'); checks++;
    const missing = await page.evaluate(async () => {
      const c = new DungeonEngineClient({workerUrl:new URL('missing/worker.js',location.href)});
      try { await c.ready; return 'accepted'; } catch(e) {return e.code;} finally {await c.close();}
    });
    assert.equal(missing,'engine_load_failed'); checks++;
    for (const asset of ['dungeon_engine.js','dungeon_engine.wasm']) {
      await page.route(`**/${asset}`,route => route.fulfill({status:404,body:'Missing engine test'}));
      const failure = await page.evaluate(async () => {
        const c = new DungeonEngineClient(); try { await c.ready; return 'accepted'; }
        catch(e) { return e.code; } finally { await c.close(); }
      });
      assert.equal(failure,'engine_load_failed'); checks++;
      await page.unroute(`**/${asset}`);
    }
    await page.goto(origin+'/nested/index.html');
    const nested = await page.evaluate(async small => { const c = new DungeonEngineClient(); try { await c.ready; return JSON.parse(await c.run(small)).outcome; } finally { await c.close(); } },small);
    assert.equal(nested,'success'); checks++;
    const closing = await browser.newPage(); await closing.goto(origin);
    await closing.evaluate(async large => { globalThis.c = new DungeonEngineClient(); await c.ready; c.run(large).catch(() => {}); },large);
    await closing.close(); checks++;
    assert.deepEqual(errors,[],'No unhandled browser errors');
    console.log(JSON.stringify({checks,dart,chrome:browser.version(),result:'PASS'},null,2));
  } finally { await browser.close(); server.close(); }
})().catch(error => { console.error(error); server.close(); process.exitCode = 1; });
