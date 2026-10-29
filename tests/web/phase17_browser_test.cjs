// Actual packaged Chrome assets and bundled samples, including boundary recovery.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const {chromium}=require('playwright');
const pkg=process.env.DA_TEST_PACKAGE,base=process.env.DA_TEST_BASE_URL;
assert.ok(pkg&&base,'Run through phase17_package_test.cjs --browser');
const teaching=fs.readFileSync(path.join(pkg,'samples/teaching.json'),'utf8');
const large=fs.readFileSync(path.join(pkg,'samples/irregular-fortress.json'),'utf8');
const over=JSON.parse(teaching);over.source.packs=Array.from({length:15},(_,i)=>({...over.source.packs[0],id:`oversize-${i}`,active:true}));
const oversized=JSON.stringify(over);
const semantic=raw=>JSON.parse(raw,(key,value)=>key==='timings_us'||key==='trace_us'?undefined:value);
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 let page;
 try {
  page=await browser.newPage({viewport:{width:1600,height:1000}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  const external=[];page.on('request',r=>{if(!r.url().startsWith(base)&&!r.url().startsWith('data:')&&!r.url().startsWith('blob:'))external.push(r.url());});
  await page.goto(base);
  const native=spawnSync(path.join(pkg,'bin/dungeon_cli.exe'),['run',path.join(pkg,'samples/teaching.json'),'--json','--events','0'],{encoding:'utf8',windowsHide:true,maxBuffer:16*1024*1024});assert.equal(native.status,0);
  const evidence=await page.evaluate(async({teaching,large,oversized})=>{
   const e=new DungeonEngineClient();
   try {
    const baseline=await e.run(teaching,5,0),retained=e.lastResult;
    const optimized=JSON.parse(await e.run(teaching,9)),accepted=e.lastResult;
    const unsupported=JSON.parse(await e.run(oversized));
    const preservedAfterOversize=e.lastResult===accepted;
    const before=e.lastResult;
    const malformed=JSON.parse(await e.run('{broken'));
    const preservedAfterInvalid=e.lastResult===before;
    const work=e.run(large);const start=performance.now();
    while(JSON.parse(e.progressJson).state!==1&&performance.now()-start<5000)await new Promise(r=>setTimeout(r,2));
    await e.cancel();const cancelled=JSON.parse(await work),preservedAfterCancel=e.lastResult===before;
    const recovery=JSON.parse(await e.run(teaching));
    return {baseline,optimized,unsupported,malformed,cancelled,preservedAfterOversize,preservedAfterInvalid,preservedAfterCancel,recovery,cancelMs:performance.now()-start};
   }finally{await e.close();}
  },{teaching,large,oversized});
  assert.deepEqual(semantic(evidence.baseline),semantic(native.stdout),'Native/packaged Wasm semantic parity');
  assert.equal(evidence.optimized.outcome,'success');assert.equal(evidence.unsupported.outcome,'unsupported_size');assert.equal(evidence.unsupported.optimal,false);
  assert.notEqual(evidence.malformed.outcome,'success');assert.equal(evidence.cancelled.outcome,'cancelled');
  for(const key of ['preservedAfterOversize','preservedAfterInvalid','preservedAfterCancel'])assert.equal(evidence[key],true,key);
  assert.equal(evidence.recovery.outcome,'success');assert.ok(evidence.cancelMs<6000);
  await page.addInitScript(raw=>{
   globalThis.pickText=raw;globalThis.written=null;
   globalThis.showOpenFilePicker=async()=>[{name:'teaching.json',getFile:async()=>new File([pickText],'teaching.json')}];
   globalThis.showSaveFilePicker=async()=>({name:'saved.json',createWritable:async()=>({write:async value=>{written=value;},close:async()=>{},abort:async()=>{}})});
  },teaching);
  await page.goto(base+'/index.html');const semantics=page.locator('flt-semantics-placeholder');await semantics.waitFor();await semantics.evaluate(n=>n.click());
  const button=name=>page.getByRole('button',{name,exact:true});
  const text=value=>page.getByText(value).or(page.getByLabel(value)).first();
  const click=async locator=>{await locator.waitFor();await locator.scrollIntoViewIfNeeded();const b=await locator.boundingBox();assert.ok(b);await page.mouse.click(b.x+b.width/2,b.y+b.height/2);await page.mouse.move(800,600);};
  const command=async name=>{await click(page.getByRole('button',{name:/Project commands/}));await click(page.getByRole('menuitem',{name}));};
  await button('Generate & solve').waitFor();
  await page.waitForFunction(()=>[...document.querySelectorAll('[role=button]')].some(n=>n.textContent==='Generate & solve'&&n.getAttribute('aria-disabled')!=='true'));
  await command(/^Open…/);if(await button('Discard changes').count())await click(button('Discard changes'));
  await text(/Small complete CLI walkthrough/).waitFor();
  await click(button('Generate & solve'));await text(/Exact allocation verified/).waitFor({timeout:30000});
  await click(button('Optimize').first());await text(/Geometry reused; exact allocation verified/).waitFor({timeout:30000});
  await command(/^Save as/);await page.waitForFunction(()=>written!==null);const saved=JSON.parse(await page.evaluate(()=>written));assert.deepEqual(saved,JSON.parse(native.stdout).result.source_project);
  await page.evaluate(()=>{pickText='{broken';});await command(/^Open…/);await text(/parse|JSON|invalid|Invalid/).waitFor();
  await page.evaluate(()=>{written=null;});await command(/^Save as/);await page.waitForFunction(()=>written!==null);assert.deepEqual(JSON.parse(await page.evaluate(()=>written)),saved,'Failed open retains source');
  await page.evaluate(raw=>{pickText=raw;},oversized);await command(/^Open…/);await text(/Opened teaching.json/).waitFor();
  assert.equal(await button('Generate & solve').isEnabled(),false,'Oversized catalogue disables combined solve');
  assert.equal(await button('Optimize').first().isEnabled(),false);
  await click(button('Generate only').first());await text(/Geometry verified; Optimize to allocate encounters/).waitFor({timeout:30000});
  assert.equal(await button('Optimize').first().isEnabled(),false,'Geometry generation preserves exact allocation cap');
  await page.evaluate(raw=>{pickText=raw;},large);await command(/^Open…/);
  await text(/Opened teaching.json/).waitFor();await click(button('Generate & solve'));await click(button('Cancel'));
  await text(/Cancelled|cancelled/).waitFor({timeout:10000});
  await command(/^New project/);if(await button('Discard changes').count())await click(button('Discard changes'));
  await page.evaluate(()=>{written=null;});await command(/^Save as/);await page.waitForFunction(()=>written!==null);
  const blank=JSON.parse(await page.evaluate(()=>written));assert.equal(blank.source.rooms.length,0);assert.equal(blank.source.packs.length,0);
  // Exercise the shipped truly empty mask, then author a buildable area with
  // actual pointer input and persist/reopen that source.
  const empty=fs.readFileSync(path.join(pkg,'samples/blank.json'),'utf8');
  await page.keyboard.press('Escape');await page.evaluate(raw=>{pickText=raw;},empty);await command(/^Open…/);
  await text(/Blank canvas - paint allowed area first/).waitFor();
  await click(button('Generate & solve'));await text(/Generation needs a nonempty building area/).waitFor({timeout:30000});
  await page.evaluate(()=>{written=null;});await command(/^Save as/);await page.waitForFunction(()=>written!==null);
  assert.equal(JSON.parse(await page.evaluate(()=>written)).source.allowed_mask.join(''),'0'.repeat(24*16),'Failed empty-mask generation keeps exact source');
  await page.keyboard.press('Escape');await click(button('Fit canvas (F)'));
  const canvas=page.getByLabel('Design tile canvas. Wheel zooms; Space or middle drag pans. Use toolbar tools to edit.',{exact:true});
  const box=await canvas.boundingBox();assert.ok(box);
  const scale=Math.min((box.width-48)/24,(box.height-48)/16);
  const tile=(x,y)=>({x:box.x+(box.width-24*scale)/2+(x+.5)*scale,y:box.y+(box.height-16*scale)/2+(y+.5)*scale});
  await click(page.getByRole('button',{name:/Shape tools/}));await click(page.getByRole('menuitem',{name:'Rectangle preset',exact:true}));
  await click(button('Add shape'));await click(page.getByRole('menuitem',{name:'Replace shape',exact:true}));
  const start=tile(1,1),end=tile(22,14);await page.mouse.move(start.x,start.y);await page.mouse.down();await page.mouse.move(end.x,end.y,{steps:3});await page.mouse.up();
  await click(button('Apply shape'));
  await page.evaluate(()=>{written=null;});await command(/^Save as/);await page.waitForFunction(()=>written!==null);
  const authored=JSON.parse(await page.evaluate(()=>written));assert.equal(authored.source.allowed_mask[0],'0'.repeat(24));assert.equal(authored.source.allowed_mask[8],'0'+'1'.repeat(22)+'0');
  await page.keyboard.press('Escape');await click(button('Generate & solve'));await text(/Exact allocation verified/).waitFor({timeout:30000});
  await page.evaluate(raw=>{pickText=raw;written=null;},JSON.stringify(authored));await command(/^Open…/);
  await text(/Opened teaching.json/).waitFor();await command(/^Save as/);await page.waitForFunction(()=>written!==null);
  assert.deepEqual(JSON.parse(await page.evaluate(()=>written)),authored,'Authored empty-mask start survives save/reopen exactly');
  await page.keyboard.press('Escape');await click(button('Generate & solve'));await text(/Exact allocation verified/).waitFor({timeout:30000});
  assert.deepEqual(external,[],'All browser runtime requests remain inside packaged origin');assert.deepEqual(errors,[]);
  const output=path.resolve(__dirname,'../../output/app');fs.mkdirSync(output,{recursive:true});await page.screenshot({path:path.join(output,'phase17-package-blank.png')});
  console.log(JSON.stringify({checks:'packaged native/Wasm parity, oversize/invalid/cancel retained results and recovery, actual UI open/save/optimize/oversize geometry-only/failed-open/cancel/New, shipped empty-mask failure then rectangle/apply/generate/save/reopen/reproduce, self-hosted requests',cancelMs:evidence.cancelMs,viewport:{width:1600,height:1000},chrome:browser.version()}));
 }catch(e){if(page)await page.screenshot({path:path.resolve(__dirname,'../../output/app/phase17-package-failure.png')}).catch(()=>{});throw e;}
 finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
