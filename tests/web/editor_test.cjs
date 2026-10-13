// Phase 9: actual Flutter/worker plus browser file-adapter transactions.
const {chromium}=require('playwright');
const fs=require('node:fs'), path=require('node:path'), http=require('node:http'), assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../../apps/flutter_ui/build/web');
const fixture=fs.readFileSync(path.resolve(__dirname,'../../datasets/allocation/standard-14.json'),'utf8');
const output=path.resolve(__dirname,'../../output/app');
const server=http.createServer((req,res)=>{
 let url=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(url==='/')url='/index.html';
 const file=path.resolve(root,`.${url}`);if(!file.startsWith(root+path.sep)){res.writeHead(404).end();return;}
 fs.readFile(file,(err,data)=>{if(err){res.writeHead(404).end();return;}res.writeHead(200,{'Content-Type':({'.js':'text/javascript','.wasm':'application/wasm','.html':'text/html','.json':'application/json','.ttf':'font/ttf'})[path.extname(file)]||'application/octet-stream'}).end(data);});
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try {
  const page=await browser.newPage({viewport:{width:1440,height:960},deviceScaleFactor:1,reducedMotion:'reduce'});
  globalThis.testPage=page; const text=(name,options={})=>page.getByText(name,options).or(page.getByLabel(name,{exact:false})).first(); const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{
   globalThis.pickText='';globalThis.written=null;globalThis.denySave=false;globalThis.pickAbort=false;globalThis.savePicks=0;
   const handle={name:'saved.dungeon.json',getFile:async()=>new File([globalThis.pickText],'opened.dungeon.json',{type:'application/json'}),createWritable:async()=>{
     if(globalThis.denySave)throw new DOMException('Test denied write','NotAllowedError');
     let value='';return {write:async text=>{value=text;},close:async()=>{globalThis.written=value;},abort:async()=>{}};
   }};
   globalThis.showOpenFilePicker=async()=>{if(globalThis.pickAbort)throw new DOMException('Test picker cancelled','AbortError');return [handle];};
   globalThis.showSaveFilePicker=async()=>{globalThis.savePicks++;if(globalThis.pickAbort)throw new DOMException('Test picker cancelled','AbortError');return handle;};
  });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  const semantics=page.locator('flt-semantics-placeholder');await semantics.waitFor();await semantics.evaluate(e=>e.click());

  const fileCommand=async command=>{
    await page.getByRole('button',{name:/Project commands/}).click();
    const item=page.getByRole('menuitem',{name:command==='save'?/^Save\s+Ctrl\+S/:/^Open…/});
    await item.click();
  };
  const saveDisabled=async()=>{
    await page.getByRole('button',{name:/Project commands/}).click();
    const value=await page.getByRole('menuitem',{name:/^Save\s+Ctrl\+S/}).getAttribute('aria-disabled');
    await page.keyboard.press('Escape');return value;
  };
  const run=page.getByRole('button',{name:'Generate & solve',exact:true});
  await run.waitFor();await page.waitForFunction(()=>Array.from(document.querySelectorAll('[role=button]')).some(e=>e.textContent==='Generate & solve'&&e.getAttribute('aria-disabled')!=='true'));
  await fileCommand('save');
  await text('saved.dungeon.json',{exact:true}).waitFor();
  let saved=await page.evaluate(()=>written);assert.equal(JSON.parse(saved).source.settings.columns,150);assert.ok(!saved.includes('"result"'));
  // Save As must request a destination even when a handle already exists.
  await page.keyboard.press('Control+Shift+s');await page.waitForFunction(()=>savePicks===2);
  await page.waitForTimeout(100);
  await page.evaluate(()=>{pickAbort=true;});
  await fileCommand('open');
  await page.waitForTimeout(150);await text('All source changes saved').waitFor();
  await page.evaluate(()=>{pickAbort=false;});
  // New uses native defaults and starts dirty, even after a clean saved project.
  await page.keyboard.press('Control+Alt+n');await text('Unsaved source changes').waitFor();
  await fileCommand('save');
  await text('All source changes saved').waitFor();
  // Open exact source through the browser picker adapter, then run real C++.
  await page.evaluate(text=>{pickText=text;},fixture);
  await fileCommand('open');
  await text('opened.dungeon.json',{exact:true}).waitFor();
  await run.click();await text('Completed. Exact allocation verified.',{exact:false}).first().waitFor({timeout:30000});
  await text('VERIFIED',{exact:true}).waitFor();
  // Choose a generated room, then inspect all three views.
  const room=page.locator('flt-semantics[role=button]').filter({hasText:/Generated room|Room 1/}).first();
  const available=await room.count(); if(available)await room.click();
  await page.getByRole('button',{name:/analyze workspace/}).click();await text('ALLOCATION OVERVIEW',{exact:true}).waitFor();
  await page.getByRole('button',{name:/play workspace/}).click();await text('EXPLORATION PREVIEW',{exact:true}).waitFor();
  await page.getByRole('button',{name:/design workspace/}).click();
  fs.mkdirSync(output,{recursive:true});await page.screenshot({path:path.join(output,'phase09-editor.png')});
  // Invalid draft cannot be saved; fixing the draft marks previous output stale.
  const inputs=page.getByRole('textbox');
  await inputs.nth(1).fill('-');await text(/Enter a whole number from 0 to 4294967295/).waitFor();
  assert.equal(await saveDisabled(),'true');
  await inputs.nth(1).fill('1');await text('STALE · previous result',{exact:true}).waitFor();
  await page.waitForTimeout(150);
  await fileCommand('open');await text('Save your changes?',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Cancel',exact:true}).click();await text('STALE · previous result',{exact:true}).waitFor();
  // Failed save preserves edits, successful save clears dirty after close only.
  await page.evaluate(()=>{denySave=true;});await fileCommand('save');
  await text(/Save failed; your project is still open/).first().waitFor();
  await text('Unsaved source changes').waitFor();
  await page.evaluate(()=>{denySave=false;});await fileCommand('save');await text('saved.dungeon.json',{exact:true}).waitFor();
  saved=await page.evaluate(()=>written);assert.equal(JSON.parse(saved).source.settings.seed,1);
  // Malformed open is transactional; its filename/source/result remain available.
  await page.evaluate(()=>{pickText='{';});await fileCommand('open');
  await text(/Open failed:/).first().waitFor();await text('saved.dungeon.json',{exact:true}).waitFor();
  await text('STALE · previous result',{exact:true}).waitFor();
  // Wide integer survives load -> unrelated edit -> canonical save.
  const big=JSON.stringify({...JSON.parse(fixture),source:{...JSON.parse(fixture).source,settings:{...JSON.parse(fixture).source.settings,threat_budget:'BIG'}}}).replace('"BIG"','9007199254740993');
  await page.evaluate(text=>{pickText=text;},big);await fileCommand('open');await text('opened.dungeon.json',{exact:true}).waitFor();
  await page.getByRole('textbox').nth(1).fill('2');await page.waitForTimeout(150);
  await fileCommand('save');await text('saved.dungeon.json',{exact:true}).waitFor();
  assert.ok((await page.evaluate(()=>written)).includes('9007199254740993'));
  // Restore known seed for successful generation; cancel a real subsequent job.
  await page.getByRole('textbox').nth(1).fill('1');await page.waitForTimeout(150);await run.click();
  await text('VERIFIED',{exact:true}).waitFor({timeout:30000});
  await run.click();await page.getByRole('button',{name:'Cancel',exact:true}).click();
  await text(/Cancelled\. The last valid result was kept/).first().waitFor();await text('VERIFIED',{exact:true}).waitFor();
  // A real C++ fixture exhausts seed 12; seed 13 is the first successful layout.
  await fileCommand('save');await text('All source changes saved').waitFor();
  const retry=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../datasets/generation/standard-150.json'),'utf8'));
  retry.source.settings.seed=12;
  await page.evaluate(s=>{pickText=s;},JSON.stringify(retry));await fileCommand('open');await text('Opened opened.dungeon.json.').waitFor();
  await run.click();await text(/First valid solution after 2 candidates; seed 13/).waitFor({timeout:30000});
  await fileCommand('save');await text('All source changes saved').waitFor();
  assert.equal(JSON.parse(await page.evaluate(()=>written)).source.settings.seed,13);
  await page.getByRole('button',{name:'Room 1',exact:true}).click();
  await page.getByRole('button',{name:'Fix room here',exact:true}).click();
  await text(/Room fixed at its current position and size/).waitFor();
  await fileCommand('save');await text('All source changes saved').waitFor();
  const pinned=JSON.parse(await page.evaluate(()=>written)).source.rooms.find(r=>r.id==='generated-1');
  assert.equal(pinned.lock_position,true);assert.equal(pinned.lock_size,true);
  assert.deepEqual(pinned.bounds,{x:6,y:54,width:19,height:12});
  await run.click();await text('VERIFIED',{exact:true}).waitFor({timeout:30000});
  await page.getByRole('button',{name:'Release room',exact:true}).click();
  await text(/Room released/).waitFor();await fileCommand('save');await text('All source changes saved').waitFor();
  assert.equal(JSON.parse(await page.evaluate(()=>written)).source.rooms.find(r=>r.id==='generated-1').lock_position,false);
  await page.getByRole('button',{name:'Switch to dark mode',exact:true}).click();
  await page.getByRole('button',{name:/Shape tools/}).hover();await page.waitForTimeout(650);
  await page.screenshot({path:path.join(output,'editor-refined-dark.png')});
  // Real download fallback; retain dirty because requesting download isn't confirmation.
  await page.evaluate(()=>{showSaveFilePicker=undefined;});
  const download=page.waitForEvent('download');await fileCommand('save');
  const artifact=await download;await artifact.saveAs(path.join(output,'phase09-download.json'));
  assert.equal(JSON.parse(fs.readFileSync(path.join(output,'phase09-download.json'),'utf8')).schema_version,1);
  await text(/Download requested/).first().waitFor();
  await page.setViewportSize({width:800,height:700});await page.getByRole('button',{name:/analyze workspace/}).click();await page.screenshot({path:path.join(output,'phase09-compact.png')});
  await page.setViewportSize({width:520,height:700});await page.getByRole('button',{name:'Project inspector',exact:true}).click();await text('INSPECTOR',{exact:true}).waitFor();
  await page.screenshot({path:path.join(output,'phase09-mobile-inspector.png')});
  assert.deepEqual(errors,[],'No unhandled browser errors');
  const hi=await browser.newPage({viewport:{width:1440,height:900},deviceScaleFactor:2});await hi.goto(`http://127.0.0.1:${server.address().port}`);await hi.waitForTimeout(1200);await hi.screenshot({path:path.join(output,'phase09-hidpi.png')});await hi.close();
  await page.close();console.log('PASS editor: real automatic seed 12→13 recovery and persistence, pin/regenerate/release, dark tooltip, views, validation, stale results, File-menu New/Open/Save, failed writes/imports, unsaved confirmation, int64, cancel, download, resizing and high DPI.');
 } catch(e) { fs.mkdirSync(output,{recursive:true}); await testPage.screenshot({path:path.join(output,'phase09-failure.png')}); fs.writeFileSync(path.join(output,'phase09-failure.html'),await testPage.locator('flt-semantics-host').innerHTML()); throw e; } finally {await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});





