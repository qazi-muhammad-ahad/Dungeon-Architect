// Real Wasm authority and real Flutter keyboard/focus/scenario workflow.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const {chromium} = require('playwright');
const root = path.resolve(__dirname, '../../apps/flutter_ui/build/web');
const output = path.resolve(__dirname, '../../output/app');
const teaching = fs.readFileSync(process.env.DA_TEST_PACKAGE ? path.join(process.env.DA_TEST_PACKAGE,'samples/teaching.json') : path.resolve(__dirname, '../../datasets/pipeline/teaching.json'), 'utf8');
const server = http.createServer((req,res) => {
  const name = new URL(req.url, 'http://localhost').pathname;
  if (name === '/') return res.writeHead(200, {'Content-Type':'text/html'}).end('<script src="engine/client.js"></script>');
  const file = path.resolve(root, '.' + name);
  if (!file.startsWith(root + path.sep)) return res.writeHead(404).end();
  fs.readFile(file, (error,data) => error ? res.writeHead(404).end() :
    res.writeHead(200, {'Content-Type': {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.css':'text/css','.ttf':'font/ttf','.otf':'font/otf','.woff':'font/woff','.woff2':'font/woff2','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon'}[path.extname(file)] || 'application/octet-stream'}).end(data));
});
const xy = p => [p.x,p.y];
function route(floor,from,to,avoid) {
  const key = p => p.join(','), queue = [[from]], seen = new Set([key(from)]);
  for (let i=0;i<queue.length;i++) {
    const path = queue[i], p = path.at(-1);
    if (key(p) === key(to)) return path.slice(1);
    for (const [dx,dy] of [[1,0],[0,1],[-1,0],[0,-1]]) {
      const next = [p[0]+dx,p[1]+dy], id = key(next);
      if (floor[next[1]]?.[next[0]] !== '1' || seen.has(id) || avoid?.join(',') === id) continue;
      seen.add(id); queue.push([...path,next]);
    }
  }
  throw Error(`No independent floor route ${from} -> ${to}`);
}
(async () => {
  if (!process.env.DA_TEST_BASE_URL) await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const packageBase = process.env.DA_TEST_BASE_URL || `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({channel:'chrome',headless:true});
  let page;
  try {
    const context = await browser.newContext({viewport:{width:1600,height:1100}});
    page = await context.newPage();
    const errors=[]; page.on('pageerror', error => errors.push(error.message));
    const base = packageBase;
    await page.goto(base);
    const evidence = await page.evaluate(async teaching => {
      const engine = new DungeonEngineClient();
      try {
        const baseline = JSON.parse(await engine.run(teaching)), baselineJob = engine.snapshotJob;
        const retained = engine.lastResult, g = baseline.result.geometry;
        const firstDoor = g.doors[0], blocked = firstDoor.tiles.map(t=>[t.x,t.y]);
        const scenario = JSON.parse(await engine.run(JSON.stringify({baseline_job:baselineJob,blocked_tiles:blocked}),11));
        const scenarioJob = scenario.scenario.snapshot_job;
        const origin = g.entrance_marker;
        const baselineMove = JSON.parse(await engine.step(baselineJob,origin.x,origin.y,1,0));
        const scenarioMove = JSON.parse(await engine.step(scenarioJob,origin.x,origin.y,1,0));
        const stillRetained = engine.lastResult === retained && engine.snapshotJob === baselineJob;
        const reset = JSON.parse(await engine.run(JSON.stringify({baseline_job:baselineJob}),11));
        return {baseline,baselineJob,scenario,blocked,baselineMove,scenarioMove,stillRetained,reset};
      } finally { await engine.close(); }
    }, teaching);
    const baseline = evidence.baseline.result, geometry = baseline.geometry, floor = geometry.layers.floor;
    assert.equal(evidence.baseline.outcome,'success'); assert.equal(evidence.baseline.optimal,true);
    assert.equal(evidence.scenario.outcome,'success'); assert.equal(evidence.scenario.optimal,true);
    assert.equal(evidence.scenario.scenario.exit_reachable,false);
    assert.equal(evidence.scenario.result.allocation.total_score,0);
    assert.equal(evidence.scenario.scenario.solver,'full_exact_rerun');
    assert.equal(evidence.stillRetained,true);
    assert.deepEqual(evidence.scenario.result.source_project,baseline.source_project);
    assert.deepEqual(evidence.reset.result.geometry.layers,geometry.layers);
    assert.deepEqual(evidence.reset.result.allocation.assignments,baseline.allocation.assignments);
    for(const p of evidence.blocked) assert.equal(evidence.scenario.result.geometry.layers.floor[p[1]][p[0]],'0');
    for(const p of [evidence.baselineMove,evidence.scenarioMove]) assert.equal(floor[p.y][p.x],'1');
    await page.addInitScript(({teaching}) => {
      globalThis.written = null;
      globalThis.showOpenFilePicker = async () => [{name:'teaching.json',getFile:async()=>new File([teaching],'teaching.json')}];
      globalThis.showSaveFilePicker = async () => ({name:'baseline.json',createWritable:async()=>({write:async value=>{written=value;},close:async()=>{},abort:async()=>{}})});
    }, {teaching});
    await page.goto(`${base}/index.html`);
    const semantics = page.locator('flt-semantics-placeholder');
    await semantics.waitFor(); await semantics.evaluate(node=>node.click());
    const button = name=>page.getByRole('button',{name,exact:true});
    const text = (value,options)=>page.getByText(value,options).or(page.getByLabel(value,options)).first();
    const click = async locator=>{
      await locator.waitFor(); await locator.scrollIntoViewIfNeeded();
      assert.ok(await locator.isEnabled(),'Control must be enabled');
      const box=await locator.boundingBox(); assert.ok(box && box.width>0 && box.height>0,'Visible control bounds');
      await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
      await page.mouse.move(800,650);
    };
    const navigate = async workspace=>{
      await click(page.getByRole('button',{name:new RegExp(`${workspace} workspace`)}));
      await page.waitForTimeout(150);
    };
    const status = () => text(/^Player: \d+, \d+ · /);
    const position = async () => {
      const node=status(); const value=(await node.getAttribute('aria-label')) || await node.innerText();
      const match=/Player: (\d+), (\d+) · (\w+)/.exec(value);
      assert.ok(match,`Readable player status: ${value}`); return {tile:[Number(match[1]),Number(match[2])],state:match[3]};
    };
    const at = async (p,state)=>text(new RegExp(`^Player: ${p[0]}, ${p[1]} · ${state || '(Exploring|Paused|Completed)'}`)).waitFor({timeout:5000});
    const move = async (from,to,useWasd=false)=>{
      const dx=to[0]-from[0],dy=to[1]-from[1]; assert.equal(Math.abs(dx)+Math.abs(dy),1);
      const key=dx===1?(useWasd?'d':'ArrowRight'):dx===-1?(useWasd?'a':'ArrowLeft'):dy===1?(useWasd?'s':'ArrowDown'):(useWasd?'w':'ArrowUp');
      // Semantic updates can trail native movement; release independently of
      // DOM observation, then replan from the authoritative displayed position.
      await page.keyboard.press(key,{delay:140});
      await page.waitForTimeout(60);
      const actual=(await position()).tile;
      assert.equal(floor[actual[1]]?.[actual[0]],'1','Every observed player tile is native floor');
      const distance=dx!==0?actual[0]-from[0]:actual[1]-from[1];
      assert.equal(dx!==0?actual[1]:actual[0],dx!==0?from[1]:from[0],'A held cardinal key cannot move diagonally');
      assert.ok(distance*(dx||dy)>=0,'Movement follows the held direction');
      for(let n=1;n<=Math.abs(distance);n++) assert.equal(floor[from[1]+dy*n]?.[from[0]+dx*n],'1','No observed cardinal segment crosses a wall');
      return actual;
    };
    const follow = async (from,path)=>{
      const target=path.at(-1)||from, avoid=target.join(',')===xy(geometry.exit_marker).join(',')?undefined:xy(geometry.exit_marker);
      let current=(await position()).tile;
      for(let i=0;i<200;i++) {
        if(current.join(',')===target.join(',')) return current;
        const next=route(floor,current,target,avoid)[0];
        current=await move(current,next,i%2===0);
      }
      throw Error(`Keyboard navigation did not reach ${target} within200 bounded presses; stopped ${current}`);
    };
    await button('Generate & solve').waitFor();
    await page.waitForFunction(()=>[...document.querySelectorAll('[role=button]')].some(node=>node.textContent==='Generate & solve' && node.getAttribute('aria-disabled')!=='true'));
    await click(page.getByRole('button',{name:/Project commands/}));
    await click(page.getByRole('menuitem',{name:/^Open…/}));
    await click(button('Discard changes'));
    await text('Small complete CLI walkthrough',{exact:false}).waitFor();
    await click(button('Generate & solve'));
    await text(/Exact allocation verified/).waitFor({timeout:30000});
    await navigate('play');
    await click(button('Start exploration'));
    const entrance=xy(geometry.entrance_marker), exit=xy(geometry.exit_marker);
    await at(entrance,'Exploring');
    // Hold against a real wall; native collision must retain the last legal tile.
    let left=[...entrance]; while(floor[left[1]]?.[left[0]-1]==='1') left[0]--;
    await page.keyboard.down('ArrowLeft');
    await at(left); await page.waitForTimeout(350); await page.keyboard.up('ArrowLeft');
    assert.deepEqual((await position()).tile,left);
    await click(button('Restart')); await at(entrance,'Exploring');
    // Keyboard modal clears held movement, and closing it does not resume keys.
    await page.keyboard.down('d'); await page.keyboard.press('e');
    const dialog=page.getByRole('alertdialog'); await dialog.waitFor();
    await page.keyboard.up('d'); await click(dialog.getByRole('button',{name:'Close',exact:true}));
    await text(/^Player: \d+, \d+ · Paused/).waitFor({timeout:5000});
    const pausedAt=await position(); assert.equal(pausedAt.state,'Paused');
    await click(button('Resume exploration')); await page.waitForTimeout(350);
    assert.deepEqual((await position()).tile,pausedAt.tile);
    // Losing canvas focus, then repeated view changes, must pause and clear keys.
    await page.keyboard.down('ArrowRight');
    await navigate('analyze'); await page.keyboard.up('ArrowRight');
    await navigate('play');
    assert.equal((await position()).state,'Paused'); const viewTile=(await position()).tile;
    await click(button('Resume exploration')); await page.waitForTimeout(350);
    assert.deepEqual((await position()).tile,viewTile);
    await click(button('Restart')); await at(entrance,'Exploring');
    // Browser-level focus loss exercises the lifecycle observer as well.
    // Playwright headless otherwise forces every page to report focused even
    // after a same-context tab switch, hiding genuine browser focus events.
    const focusSession=await page.context().newCDPSession(page);
    await focusSession.send('Emulation.setFocusEmulationEnabled',{enabled:false});
    const focusBefore=await page.evaluate(()=>({focused:document.hasFocus(),visibility:document.visibilityState}));
    await page.keyboard.down('ArrowRight');
    const other=await page.context().newPage(); await other.goto('about:blank'); await other.bringToFront();
    await page.waitForTimeout(200);
    const focusAway=await page.evaluate(()=>({focused:document.hasFocus(),visibility:document.visibilityState}));
    console.log(JSON.stringify({focusBefore,focusAway}));
    assert.ok(!focusAway.focused||focusAway.visibility==='hidden','Browser must actually lose focus or visibility during the lifecycle check');
    await page.bringToFront(); await page.keyboard.up('ArrowRight');
    await text(/^Player: \d+, \d+ · Paused/).waitFor({timeout:5000});
    assert.equal((await position()).state,'Paused'); await other.close();
    await click(button('Restart')); await at(entrance,'Exploring');
    const actor=baseline.allocation.actors[0]; assert.ok(actor,'Teaching allocation has a reconstructed actor');
    // Find a reachable tile near the actor without crossing the completion tile.
    let approach, actorPath;
    for(let dy=-2;dy<=2&&!approach;dy++) for(let dx=-2;dx<=2&&!approach;dx++) {
      if(Math.abs(dx)+Math.abs(dy)>2) continue;
      const candidate=[actor.tile.x+dx,actor.tile.y+dy]; if(floor[candidate[1]]?.[candidate[0]]!=='1'||candidate.join(',')===exit.join(',')) continue;
      try { actorPath=route(floor,entrance,candidate,exit); approach=candidate; } catch(_) {}
    }
    assert.ok(approach,'Reachable approach to nonblocking encounter');
    await follow(entrance,actorPath); await page.keyboard.press('e'); await dialog.waitFor();
    const pack=baseline.source_project.source.packs.find(p=>p.id===actor.pack_id);
    await text(new RegExp(`Pack: ${pack.name}`)).waitFor();
    await text(new RegExp(`Room: ${actor.room_id}`)).waitFor();
    await text(new RegExp(`Threat: ${pack.threat}`)).waitFor(); await text(new RegExp(`Score: ${pack.score}`)).waitFor();
    await click(dialog.getByRole('button',{name:'Close',exact:true})); await click(button('Resume exploration'));
    await follow(approach,route(floor,approach,exit)); await at(exit,'Completed');
    await text(/Exit reached.*exploration complete/).waitFor();
    await click(button('Restart')); await at(entrance,'Exploring');
    // Use the public corridor-section control, verify stale assignments and an
    // actual sealed exit, then verify restoration and file persistence.
    await navigate('analyze');
    await click(text('Corridor section',{exact:true}));
    await click(text(geometry.corridors[0].id,{exact:true}));
    await click(button('Block width section'));
    await text('SCENARIO ASSIGNMENTS STALE',{exact:true}).waitFor();
    await click(button('Apply scenario'));
    await text(/Exit disconnected from entrance/).waitFor({timeout:30000});
    await text(/score 14 → 0/).waitFor();
    await navigate('play');
    assert.equal(await button('Start exploration').isEnabled(),false);
    await text(/Exit disconnected from entrance/).waitFor();
    await navigate('analyze');
    await click(page.getByRole('button',{name:/Project commands/})); await click(page.getByRole('menuitem',{name:/^Save as/}));
    await page.waitForFunction(()=>written!==null);
    const saved=JSON.parse(await page.evaluate(()=>written));
    assert.deepEqual(saved,baseline.source_project,'Save contains exact baseline source, no temporary blocks/allocation');
    await click(button('Restore baseline'));
    await text(/Baseline restored/).waitFor();
    await navigate('play'); await click(button('Start exploration')); await at(entrance,'Exploring');
    await navigate('design'); await navigate('play'); await navigate('analyze'); await navigate('play');
    assert.equal((await position()).state,'Paused');
    // Reopening source clears every derived scenario/session. A later settings
    // edit must invalidate the new session before another generation can run.
    await click(page.getByRole('button',{name:/Project commands/})); await click(page.getByRole('menuitem',{name:/^Open…/}));
    await text('No active exploration session',{exact:true}).waitFor();
    assert.equal(await button('Start exploration').isEnabled(),false);
    await click(button('Generate & solve')); await text(/Exact allocation verified/).waitFor({timeout:30000});
    await click(button('Start exploration')); await at(entrance,'Exploring');
    const budgetField=page.getByRole('textbox',{name:'Threat budget',exact:true});
    await click(budgetField); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText('2'); await page.keyboard.press('Tab');
    await text('No active exploration session',{exact:true}).waitFor();
    assert.equal(await button('Start exploration').isEnabled(),false);
    fs.mkdirSync(output,{recursive:true}); await page.screenshot({path:path.join(output,'phase14-15-play.png')});
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({checks:'Wasm scenario baseline/reset; real WASD/arrows/wall/door/actor/exit/restart/modal/focus/view transitions; sealed-exit scenario; baseline-only save',entrance,exit,actor:actor.pack_id}));
  } catch(error) {
    fs.mkdirSync(output,{recursive:true});
    if(page && !page.isClosed()) {
      await page.screenshot({path:path.join(output,'phase14-15-failure.png')}).catch(()=>{});
      await page.content().then(html=>fs.writeFileSync(path.join(output,'phase14-15-failure.html'),html)).catch(()=>{});
    }
    throw error;
  } finally {await browser.close();if (server.listening) await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
