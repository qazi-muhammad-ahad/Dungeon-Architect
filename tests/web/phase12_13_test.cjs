// Real release-engine telemetry/isolation checks; coordinator runs after Wasm build.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const {chromium} = require('playwright');
const root = path.resolve(__dirname, '../../apps/flutter_ui/build/web');
const teaching = fs.readFileSync(process.env.DA_TEST_PACKAGE ? path.join(process.env.DA_TEST_PACKAGE,'samples/teaching.json') : path.resolve(__dirname, '../../datasets/pipeline/teaching.json'), 'utf8');
const large = fs.readFileSync(process.env.DA_TEST_PACKAGE ? path.join(process.env.DA_TEST_PACKAGE,'samples/irregular-fortress.json') : path.resolve(__dirname, '../../datasets/allocation/standard-14.json'), 'utf8');
const server = http.createServer((req,res) => {
  const name = new URL(req.url, 'http://localhost').pathname;
  if (name === '/') return res.writeHead(200, {'Content-Type':'text/html'}).end('<script src="engine/client.js"></script>');
  const file = path.resolve(root, '.' + name);
  if (!file.startsWith(root + path.sep)) return res.writeHead(404).end();
  fs.readFile(file, (error,data) => error ? res.writeHead(404).end() :
    res.writeHead(200, {'Content-Type': {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.css':'text/css','.ttf':'font/ttf','.otf':'font/otf','.woff':'font/woff','.woff2':'font/woff2','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon'}[path.extname(file)] || 'application/octet-stream'}).end(data));
});
(async () => {
  if (!process.env.DA_TEST_BASE_URL) await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const packageBase = process.env.DA_TEST_BASE_URL || `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({channel:'chrome',headless:true});
  let page;
  try {
    page = await browser.newPage({viewport:{width:1600,height:1100}});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(packageBase);
    const evidence = await page.evaluate(async ({teaching,large}) => {
      const editor = new DungeonEngineClient(), benchmark = new DungeonEngineClient();
      try {
        await Promise.all([editor.ready, benchmark.ready]);
        const accepted = JSON.parse(await editor.run(teaching,5,4096,1));
        const retained = editor.lastResult, snapshot = editor.snapshotJob;
        const traces = [], measurements = [];
        for (const cap of [0,1,4096]) {
          const report = JSON.parse(await benchmark.run(teaching,5,cap,1));
          const metrics = JSON.parse(await benchmark.metrics());
          let cursor = 0, batch, events = [];
          do {
            batch = JSON.parse(await benchmark.trace(cursor,7));
            events.push(...batch.events); cursor = batch.next_cursor;
          } while (cursor < batch.total);
          traces.push({cap,report,events,batch}); measurements.push(metrics);
          if (editor.lastResult !== retained || editor.snapshotJob !== snapshot) throw Error('Benchmark replaced editor output');
        }
        const pending = benchmark.run(large), beforeCancel = performance.now();
        while (JSON.parse(benchmark.progressJson).state !== 1 && performance.now()-beforeCancel < 5000)
          await new Promise(resolve => setTimeout(resolve,2));
        await benchmark.cancel();
        const cancelled = JSON.parse(await pending), cancelMs = performance.now()-beforeCancel;
        const cancelledTrace = JSON.parse(await benchmark.trace());
        const marker = accepted.result.geometry.entrance_marker;
        const move = JSON.parse(await editor.step(snapshot,marker.x,marker.y,1,0));
        return {accepted,traces,measurements,cancelled,cancelledTrace,cancelMs,move,
          retained:editor.lastResult===retained && editor.snapshotJob===snapshot};
      } finally { await Promise.all([editor.close(), benchmark.close()]); }
    }, {teaching,large});
    for (const {cap,report,events,batch} of evidence.traces) {
      assert.deepEqual(report.result,evidence.accepted.result,'trace options preserve authoritative output');
      assert.ok(batch.total <= 4096); assert.equal(events.length,batch.total);
      if (cap === 0) { assert.equal(events.length,0); assert.equal(batch.truncated,true); }
      events.forEach((event,i) => {
        assert.equal(event.schema_version,1); assert.equal(event.run_id,batch.run_id); assert.equal(event.sequence,i);
        assert.ok(['generation','routing','allocation'].includes(event.stage));
        assert.ok(Array.isArray(event.affected_ids)); assert.ok(event.input_revision);
      });
      assert.equal(batch.schema_version,1);
    }
    assert.ok(evidence.traces[2].events.some(e => e.event.kind === 'reconstruct'));
    assert.ok(evidence.traces[2].events.some(e => e.event.kind === 'state_feasible'));
    for (const metrics of evidence.measurements) for (const stage of ['generation','routing','allocation']) {
      assert.equal(metrics[stage].timing_domain,'steady_clock_wall_including_validation_and_cooperative_yields');
      for (const value of Object.values(metrics[stage].timings_us)) assert.ok(Number.isFinite(value) && value >= 0);
      assert.ok(metrics[stage].trace_us >= 0);
    }
    assert.equal(evidence.cancelled.outcome,'cancelled'); assert.equal(evidence.cancelled.optimal,false);
    assert.ok(evidence.cancelMs < 5000,'responsive cancellation under5s');
    assert.ok(evidence.cancelledTrace.events.length <=128); assert.ok(evidence.retained);
    assert.equal(evidence.accepted.result.geometry.layers.floor[evidence.move.y][evidence.move.x],'1');
    console.log(JSON.stringify({engineChecks:'trace metadata, bounded events, immutable output, isolated workers, cancellation',cancelMs:evidence.cancelMs}));
    // Real Flutter workflow exercises the public Analyze controls and file export.
    await page.addInitScript(({teaching}) => {
      globalThis.written = null;
      globalThis.showOpenFilePicker = async () => [{name:'teaching.json',getFile:async()=>new File([teaching],'teaching.json')}];
      globalThis.showSaveFilePicker = async () => ({name:'analysis.json',createWritable:async()=>({write:async value=>{written=value;},close:async()=>{},abort:async()=>{}})});
    }, {teaching});
    await page.goto(`${packageBase}/index.html`);
    const semantics = page.locator('flt-semantics-placeholder');
    await semantics.waitFor(); await semantics.evaluate(node=>node.click());
    const button = name=>page.getByRole('button',{name,exact:true});
    const text = (value,options)=>page.getByText(value,options).or(page.getByLabel(value,options)).first();
    const pointerClick = async locator=>{
      await locator.waitFor(); await locator.scrollIntoViewIfNeeded();
      assert.ok(await locator.isEnabled(),'Control must be enabled');
      const box=await locator.boundingBox(); assert.ok(box && box.width>0 && box.height>0,'Control must have visible bounds');
      await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
      await page.mouse.move(800,650);
    };
    const navigate = async workspace=>{
      await pointerClick(page.getByRole('button',{name:new RegExp(`${workspace} workspace`)}));
      await page.mouse.move(800,650); await page.waitForTimeout(500);
    };
    await button('Generate & solve').waitFor();
    await page.waitForFunction(()=>[...document.querySelectorAll('[role=button]')].some(node=>node.textContent==='Generate & solve' && node.getAttribute('aria-disabled')!=='true'));
    await page.getByRole('button',{name:/Project commands/}).click();
    await page.getByRole('menuitem',{name:/^Open…/}).click();
    await button('Discard changes').click();
    await text('Small complete CLI walkthrough',{exact:false}).waitFor();
    await button('Generate & solve').click();
    await text(/Exact allocation verified/).waitFor({timeout:30000});
    await navigate('analyze');
    await pointerClick(button('Step trace'));
    await text(/"sequence":0/).waitFor();
    await pointerClick(button('Inspect trace JSON'));
    const traceDialog=page.getByRole('alertdialog');
    await traceDialog.waitFor();
    await page.context().grantPermissions(['clipboard-read','clipboard-write']);
    await pointerClick(traceDialog.getByRole('button',{name:'Copy JSON',exact:true}));
    await page.waitForTimeout(200);
    const traceJson=await page.evaluate(()=>navigator.clipboard.readText());
    assert.ok(traceJson.includes('fnv1a32-'));
    const shownTrace=JSON.parse(traceJson);
    assert.ok(Array.isArray(shownTrace) && shownTrace.length>0);
    assert.equal(shownTrace[0].sequence,0); assert.equal(shownTrace[0].schema_version,1);
    await pointerClick(button('Close'));
    await pointerClick(button('Play trace'));
    await navigate('design');
    await navigate('analyze');
    await button('Play trace').waitFor(); // Leaving Analyze pauses its timer.
    const choose = async name=>{
      await pointerClick(text(/^(Trace|BSP tree|DP inspector|Metrics|Benchmarks)$/));
      await pointerClick(text(name,{exact:true}));
    };
    await choose('BSP tree');
    await text(/Preserved fixed features/).waitFor();
    await choose('DP inspector');
    await text(/Candidate events are only actual examined submasks/).waitFor();
    await choose('Benchmarks');
    const field = async (name,value)=>{
      const input=page.getByRole('textbox',{name,exact:true});
      await pointerClick(input); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(value); await page.keyboard.press('Tab');
    };
    await field('Axis points','0'); await field('Repeats','2');
    await text(/Workload preview: 1 points x 2 repeats = 2 sequential jobs; seed 42/).waitFor();
    await pointerClick(button('Run benchmark'));
    await text(/Completed · 2\/2 measured runs/).waitFor({timeout:60000});
    const exportButton=button('Export benchmark JSON');
    for(let attempt=0;attempt<10;attempt++) {
      if(await exportButton.count() && await exportButton.isVisible()) break;
      await page.mouse.move(800,300); await page.mouse.wheel(0,180); await page.waitForTimeout(100);
    }
    await pointerClick(exportButton);
    await page.waitForFunction(()=>written!==null);
    const exported=JSON.parse(await page.evaluate(()=>written));
    assert.equal(exported.schema_version,1); assert.equal(exported.records.length,2);
    exported.records.forEach(record=>{
      assert.equal(record.seed,42); assert.equal(record.parameters.room_count,16);
      assert.equal(record.value,0); assert.equal(record.axis,'packs');
      assert.equal(record.metrics.instrumentation.environment,'wasm-web-worker');
    });
    fs.mkdirSync(path.resolve(__dirname,'../../output/app'),{recursive:true});
    await page.screenshot({path:path.resolve(__dirname,'../../output/app/phase12-13-analyze.png')});
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({checks:'trace bounds, metadata, real reconstruction, output invariance, isolated workers, cancellation',cancelMs:evidence.cancelMs}));
  } catch (error) {
    const output=path.resolve(__dirname,'../../output/app');
    fs.mkdirSync(output,{recursive:true});
    if(page && !page.isClosed()) {
      await page.screenshot({path:path.join(output,'phase12-13-failure.png')}).catch(()=>{});
      await page.content().then(html=>fs.writeFileSync(path.join(output,'phase12-13-failure.html'),html)).catch(()=>{});
    }
    throw error;
  } finally { await browser.close(); if (server.listening) await new Promise(resolve => server.close(resolve)); }
})().catch(error => { console.error(error); process.exitCode=1; });
