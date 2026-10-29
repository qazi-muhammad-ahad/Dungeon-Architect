// Real Chrome file lifecycle, dirty-close guard, worker cleanup and responsive UI.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const {chromium} = require('playwright');
const root = path.resolve(__dirname,'../../apps/flutter_ui/build/web');
const output = path.resolve(__dirname,'../../output/app');
const teaching = fs.readFileSync(path.resolve(__dirname,'../../datasets/pipeline/teaching.json'),'utf8');
const standard = fs.readFileSync(path.resolve(__dirname,'../../datasets/allocation/standard-14.json'),'utf8');
const server = http.createServer((req,res)=>{
  const name=new URL(req.url,'http://localhost').pathname;
  if(name==='/probe') return res.writeHead(200,{'Content-Type':'text/html'}).end('<script src="engine/client.js"></script>');
  const file=path.resolve(root,'.'+name);
  if(!file.startsWith(root+path.sep)) return res.writeHead(404).end();
  fs.readFile(file,(error,data)=>error?res.writeHead(404).end():res.writeHead(200,{'Content-Type':{'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.ttf':'font/ttf','.otf':'font/otf','.png':'image/png','.svg':'image/svg+xml'}[path.extname(file)]||'application/octet-stream'}).end(data));
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const browser=await chromium.launch({channel:'chrome',headless:true});
  try {
    const base=`http://127.0.0.1:${server.address().port}`;
    const page=await browser.newPage(); const errors=[]; page.on('pageerror',e=>errors.push(e.message));
    await page.goto(`${base}/probe`);
    await page.addScriptTag({path:path.resolve(__dirname,'../../apps/flutter_ui/web/engine/files.js')});
    const files=await page.evaluate(async()=>{
      const unload=()=>{const event=new Event('beforeunload',{cancelable:true});dispatchEvent(event);return event.defaultPrevented;};
      const f=new DungeonFiles(), states=[unload()]; f.setDirty(true); states.push(unload());
      let writes=0,aborts=0; const old={name:'old.json'}, next={name:'next.json',createWritable:async()=>({write:async()=>{writes++;},close:async()=>{},abort:async()=>{aborts++;}})};
      f.handle=old; globalThis.showSaveFilePicker=async()=>next;
      const outcomes=[];
      for(const stage of ['picker','create','write','close']) {
        const fail=()=>{throw new DOMException('Cancelled or failed','AbortError');};
        globalThis.showSaveFilePicker=stage==='picker'?fail:async()=>({name:'failed.json',createWritable:stage==='create'?fail:async()=>({write:stage==='write'?fail:async()=>{},close:stage==='close'?fail:async()=>{},abort:async()=>{aborts++;}})});
        try {await f.save('draft','test.json',true);outcomes.push(false);} catch {outcomes.push(f.handle===old&&f.dirty&&unload());}
      }
      globalThis.showSaveFilePicker=async()=>next;
      await f.save('draft','test.json',true); const adopted=f.handle===next;
      // Persistence bridge does not clear dirtiness; controller does so only
      // after receiving and accepting the completed write result.
      states.push(unload()); f.setDirty(false); states.push(unload()); f.setDirty(true); f.dispose(); states.push(unload());
      for(let i=0;i<100;i++) {const temp=new DungeonFiles();temp.setDirty(true);temp.dispose();}
      states.push(unload());return {states,outcomes,adopted,writes,aborts};
    });
    assert.deepEqual(files.states,[false,true,true,false,false,false]);
    assert.deepEqual(files.outcomes,[true,true,true,true]); assert.equal(files.adopted,true); assert.equal(files.writes,1); assert.equal(files.aborts,2);
    console.log('Chrome file persistence: failed/cancelled picker/create/write/close preserve dirty+handle; clean/dirty/disposed beforeunload;100 listener lifecycles passed');
    if(process.argv.includes('--files-only')) return;
    const cycles=await page.evaluate(async ({teaching,standard})=>{
      let live=0,created=0,terminated=0; const NativeWorker=globalThis.Worker;
      globalThis.Worker=class extends NativeWorker {constructor(...args){super(...args);live++;created++;}terminate(){live--;terminated++;return super.terminate();}};
      const checks=[];
      for(let i=0;i<12;i++) {
        const e=new DungeonEngineClient();
        const edited=JSON.parse(await e.run(JSON.stringify({project_json:teaching,command:{type:'paint',allowed:true,tiles:[{x:0,y:0}]}}),8));
        const report=JSON.parse(await e.run(edited.project_json));
        const optimized=JSON.parse(await e.run(edited.project_json,9)); const retained=e.lastResult;
        const origin=optimized.result.geometry.entrance_marker;
        const moved=JSON.parse(await e.step(e.snapshotJob,origin.x,origin.y,1,0));
        const malformed=JSON.parse(await e.run('{broken'));
        const work=e.run(standard); await new Promise(resolve=>setTimeout(resolve,10)); await e.cancel();
        const cancelled=JSON.parse(await work);
        const valid=edited.outcome==='success'&&report.outcome==='success'&&optimized.outcome==='success'&&malformed.outcome!=='success'&&cancelled.outcome==='cancelled'&&e.lastResult===retained&&optimized.result.geometry.layers.floor[moved.y][moved.x]==='1';
        await e.close(); await e.close(); checks.push(valid&&live===0&&e.pending.size===0);
      }
      const active=new DungeonEngineClient(); await active.ready;
      const running=active.run(standard).catch(error=>error.code); await new Promise(resolve=>setTimeout(resolve,10));
      await active.close(); await running;
      checks.push(active.closed&&active.pending.size===0&&live===0);
      const stalledUrl=URL.createObjectURL(new Blob(['self.onmessage=()=>{}'],{type:'text/javascript'}));
      const stalled=new DungeonEngineClient({workerUrl:stalledUrl}); stalled.ready.catch(()=>{});
      const started=performance.now(); await stalled.close(); const stalledCloseMs=performance.now()-started; URL.revokeObjectURL(stalledUrl);
      checks.push(stalled.closed&&stalled.pending.size===0&&live===0&&stalledCloseMs<3500);
      return {checks,live,created,terminated,stalledCloseMs};
    },{teaching,standard});
    assert.ok(cycles.checks.every(Boolean),JSON.stringify(cycles)); assert.equal(cycles.live,0); assert.equal(cycles.created,cycles.terminated);
    console.log(`Chrome worker lifecycle:12 edit/generate/optimize/move/fail/cancel/close cycles +active/stalled close,${cycles.created} created/${cycles.terminated} terminated; pending maps empty; stalled close ${cycles.stalledCloseMs.toFixed(1)}ms`);
    if(process.argv.includes('--lifecycle-only')) return;
    await page.close();
    for(const [width,height,dpr] of [[1600,1000,1],[1024,768,1],[800,600,1],[1280,800,1.25],[1280,800,2]]) {
      const context=await browser.newContext({viewport:{width,height},deviceScaleFactor:dpr});
      const ui=await context.newPage(); ui.on('pageerror',e=>errors.push(e.message));
      ui.on('console',message=>{if(message.type()==='error') errors.push(message.text());});
      const long=JSON.parse(teaching); long.source.name=('Long project '+ 'Masonry corridor encounter '.repeat(10)).slice(0,250);
      for(const r of long.source.rooms) r.name='Long room '+ 'Stone archive '.repeat(15);
      const proto=long.source.packs[0]; long.source.packs=Array.from({length:100},(_,i)=>({...proto,id:`catalog-${i}`,name:(`Pack ${i} `+'Ancient sentinel '.repeat(15)).slice(0,250),active:i<2}));
      await ui.addInitScript(raw=>{globalThis.testProjectRaw=raw;globalThis.showOpenFilePicker=async()=>[{name:'long-catalog.json',getFile:async()=>new File([globalThis.testProjectRaw],'long-catalog.json')}];},JSON.stringify(long));
      await ui.goto(`${base}/index.html`); const semantics=ui.locator('flt-semantics-placeholder'); await semantics.waitFor(); await semantics.evaluate(n=>n.click());
      const click=async locator=>{await locator.waitFor();await locator.scrollIntoViewIfNeeded();const b=await locator.boundingBox();assert.ok(b&&b.width>0&&b.height>0);await ui.mouse.click(b.x+b.width/2,b.y+b.height/2);await ui.mouse.move(width/2,height/2);};
      const run=()=>ui.getByRole('button',{name:/^(Generate & solve|Run)$/});
      await run().waitFor();
      await click(ui.getByRole('button',{name:/Project commands/})); await click(ui.getByRole('menuitem',{name:/^Open…/}));
      const discard=ui.getByRole('button',{name:'Discard changes',exact:true}); if(await discard.count()) await click(discard);
      await ui.getByText(/Long project/).or(ui.getByLabel(/Long project/)).first().waitFor({timeout:10000});
      await click(run());
      await ui.getByText(/Exact allocation verified/).or(ui.getByLabel(/Exact allocation verified/)).first().waitFor({timeout:30000});
      await ui.screenshot({path:path.join(output,`phase16-${width}x${height}-dpr${dpr}.png`)});
      if(width<980) await click(ui.getByRole('button',{name:'Project inspector',exact:true}));
      const lastPack=ui.getByText(/Pack 99 /).or(ui.getByLabel(/Pack 99 /)).first();
      await ui.mouse.move(width-130,height/2); await ui.mouse.wheel(0,100000); await ui.waitForTimeout(250);
      await lastPack.waitFor({timeout:5000});
      // Flutter semantics preserves unscrolled paragraph layout bounds even
      // when the painted row is clipped to two lines. Use real wheel input and
      // inspect the resulting screenshot for the final row, rather than claim
      // DOM geometry establishes paint visibility.
      for(let attempt=0;attempt<16;attempt++) {await ui.mouse.wheel(0,2000);await ui.waitForTimeout(60);}
      await ui.screenshot({path:path.join(output,`phase16-catalog-${width}-dpr${dpr}.png`)});
      await ui.mouse.wheel(0,-100000); await ui.waitForTimeout(250);
      if(width<980) await ui.keyboard.press('Escape');
      if(width===800) {
        await click(ui.getByRole('button',{name:'Hide',exact:true}));
        await click(ui.getByRole('button',{name:'Fit canvas (F)',exact:true}));
        await ui.screenshot({path:path.join(output,'phase16-800-map-expanded.png')});
      }
      if(width===1600) {
        const seed=ui.getByRole('textbox',{name:/^Seed/}).first();
        await seed.scrollIntoViewIfNeeded(); await seed.fill('-1');
        await ui.getByText('Enter a whole number from 0 to 4294967295.').or(ui.getByLabel('Enter a whole number from 0 to 4294967295.')).first().waitFor();
        assert.equal(await run().isEnabled(),false,'Invalid numeric entry disables run');
        await seed.fill('42'); await ui.waitForFunction(()=>[...document.querySelectorAll('[role=button]')].some(n=>n.textContent==='Generate & solve'&&n.getAttribute('aria-disabled')!=='true'));
        await click(run()); await ui.getByText(/Exact allocation verified/).or(ui.getByLabel(/Exact allocation verified/)).first().waitFor({timeout:30000});
        await click(ui.getByRole('button',{name:'Zoom in',exact:true}));
        await ui.screenshot({path:path.join(output,'phase16-zoom.png')});
        await click(ui.getByRole('button',{name:'Fit canvas (F)',exact:true}));
        // Traverse from a real pointer-focused control using Tab and activate a
        // workspace with Enter; collect actual browser-focused semantic labels.
        await click(ui.getByRole('button',{name:/design workspace/}));
        const focusLabels=[];
        for(let tab=0;tab<5;tab++) {await ui.keyboard.press('Tab');focusLabels.push(await ui.evaluate(()=>document.activeElement?.getAttribute('aria-label')||document.activeElement?.textContent||''));}
        assert.ok(focusLabels.some(Boolean),'Tab exposes a labeled semantic focus target');
        await ui.screenshot({path:path.join(output,'phase16-keyboard-focus.png')});
        const play=ui.getByRole('button',{name:/play workspace/});
        await play.focus(); await ui.keyboard.press('Enter');
        await click(ui.getByRole('button',{name:'Start exploration',exact:true}));
        await ui.getByText(/^Player: /).or(ui.getByLabel(/^Player: /)).first().waitFor();
        await ui.screenshot({path:path.join(output,'phase16-play.png')});
        console.log(`Chrome numeric recovery and keyboard focus labels: ${JSON.stringify(focusLabels)}`);
        await click(ui.getByRole('button',{name:/design workspace/}));
        await ui.evaluate(raw=>{globalThis.testProjectRaw=raw;},standard);
        await click(ui.getByRole('button',{name:/Project commands/})); await click(ui.getByRole('menuitem',{name:/^Open…/}));
        if(await discard.count()) await click(discard);
        await run().waitFor(); await click(run());
        await ui.getByText(/Exact allocation verified/).or(ui.getByLabel(/Exact allocation verified/)).first().waitFor({timeout:30000});
        await click(run());
        const cancel=ui.getByRole('button',{name:'Cancel',exact:true}); await click(cancel);
        await ui.getByText(/Cancelled|cancelled/).or(ui.getByLabel(/Cancelled|cancelled/)).first().waitFor({timeout:10000});
        assert.equal(await ui.getByLabel('Design tile canvas. Wheel zooms; Space or middle drag pans. Use toolbar tools to edit.',{exact:true}).count(),1);
        await ui.screenshot({path:path.join(output,'phase16-cancel-retained.png')});
        console.log('Chrome loading/cancel retains a rendered previous map');
      }
      assert.equal(await ui.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'No browser-level horizontal overflow');
      await context.close(); console.log(`Chrome responsive long names/100 packs: ${width}x${height} DPR${dpr}`);
    }
    assert.deepEqual(errors,[]); console.log('Phase16 Chrome checks passed');
  } catch(error) {
    const pages=browser.contexts().flatMap(context=>context.pages());
    const last=pages.at(-1);
    if(last) {await last.screenshot({path:path.join(output,'phase16-failure.png')});fs.writeFileSync(path.join(output,'phase16-failure-semantics.txt'),await last.locator('body').innerText()+'\n'+await last.locator('flt-semantics-host').innerHTML().catch(()=>''));}
    throw error;
  } finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
