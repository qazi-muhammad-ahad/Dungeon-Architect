// Phase 10 end-to-end: pointer input in built Flutter + real native Wasm edits.
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../../apps/flutter_ui/build/web'),output=path.resolve(__dirname,'../../output/app');
const server=http.createServer((req,res)=>{
 const name=new URL(req.url,'http://localhost').pathname;
 const file=path.resolve(root,'.'+(name==='/'?'/index.html':decodeURIComponent(name)));
 if(!file.startsWith(root+path.sep)){res.writeHead(404).end();return;}
 fs.readFile(file,(e,data)=>{if(e){res.writeHead(404).end();return;}res.writeHead(200,{'Content-Type':({'.js':'text/javascript','.wasm':'application/wasm','.html':'text/html','.json':'application/json','.ttf':'font/ttf'})[path.extname(file)]||'application/octet-stream'}).end(data);});
});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'chrome',headless:true});
 let page;
 try {
  fs.mkdirSync(output,{recursive:true});
  page=await browser.newPage({viewport:{width:1600,height:1000},deviceScaleFactor:2,reducedMotion:'reduce'});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{
   globalThis.written=null;globalThis.pickText='';
   const handle={name:'canvas.json',getFile:async()=>new File([pickText],'canvas.json'),createWritable:async()=>({write:async s=>{written=s;},close:async()=>{},abort:async()=>{}})};
   globalThis.showSaveFilePicker=async()=>handle;globalThis.showOpenFilePicker=async()=>[handle];
  });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  const enable=async()=>{const p=page.locator('flt-semantics-placeholder');await p.waitFor();await p.evaluate(e=>e.click());};await enable();
  const button=name=>page.getByRole('button',{name,exact:true});
  const text=name=>page.getByText(name).or(page.getByLabel(name)).first();

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
  const save=async()=>{await page.waitForFunction(()=>Array.from(document.querySelectorAll('[role=button]')).some(e=>e.textContent==='Generate & solve'&&e.getAttribute('aria-disabled')!=='true'));await page.evaluate(()=>{written=null;});await fileCommand('save');await page.waitForFunction(()=>written!==null);await text('All source changes saved').waitFor();return JSON.parse(await page.evaluate(()=>written));};
  let original=await save();
  const canvas=page.getByLabel('Design tile canvas. Wheel zooms; Space or middle drag pans. Use toolbar tools to edit.',{exact:true});
  const fit=async(n=150)=>{await button('Fit canvas (F)').click();const b=await canvas.boundingBox();assert.ok(b);const s=Math.min((b.width-48)/n,(b.height-48)/n);return (x,y)=>({x:b.x+(b.width-n*s)/2+(x+.5)*s,y:b.y+(b.height-n*s)/2+(y+.5)*s});};
  const click=async p=>page.mouse.click(p.x,p.y);
  const drag=async(a,b)=>{await page.mouse.move(a.x,a.y);await page.mouse.down();await page.mouse.move(b.x,b.y,{steps:1});await page.mouse.up();};
  let tile=await fit();
  await button('Erase allowed tiles').click();await click(tile(0,0));
  let doc=await save();assert.equal(doc.source.allowed_mask[0][0],'0');assert.equal(doc.source.allowed_mask.join('').split('0').length-1,1);
  await button('Undo stroke (Ctrl+Z)').click();doc=await save();assert.deepEqual(doc.source.allowed_mask,original.source.allowed_mask);
  await button('Redo stroke (Ctrl+Shift+Z)').click();doc=await save();assert.equal(doc.source.allowed_mask[0][0],'0');
  await button('1 tile brush').click();await page.getByRole('menuitem',{name:'3 tile brush',exact:true}).click();
  await click(tile(0,0));doc=await save();assert.equal(doc.source.allowed_mask.join('').split('0').length-1,4);
  await button('Undo stroke (Ctrl+Z)').click();await save();
  await button('3 tile brush').click();await page.getByRole('menuitem',{name:'1 tile brush',exact:true}).click();
  // One fast pointer move must erase all 21 cells, as one undo gesture.
  await drag(tile(10,10),tile(30,10));doc=await save();assert.equal(doc.source.allowed_mask[10].slice(10,31),'0'.repeat(21));
  await button('Undo stroke (Ctrl+Z)').click();doc=await save();assert.equal(doc.source.allowed_mask[10],'1'.repeat(150));
  // Cursor-centered wheel zoom preserves the tile under the cursor at DPR 2.
  const anchor=tile(50,50);await page.mouse.move(anchor.x,anchor.y);await page.mouse.wheel(0,-300);await text('Tile 50, 50').waitFor();
  await click(anchor);doc=await save();assert.equal(doc.source.allowed_mask[50][50],'0');
  tile=await fit();
  const panStart=tile(75,75);await page.mouse.move(panStart.x,panStart.y);await page.mouse.down({button:'middle'});await page.mouse.move(panStart.x+37,panStart.y+29);await page.mouse.up({button:'middle'});
  const shifted=tile(40,40);await click({x:shifted.x+37,y:shifted.y+29});doc=await save();assert.equal(doc.source.allowed_mask[40][40],'0');tile=await fit();
  // Shape is native-previewed, and cannot alter the saved source before Apply.
  await page.getByRole('button',{name:/Shape tools/}).click();await page.getByRole('menuitem',{name:'Rectangle preset',exact:true}).click();
  await button('Add shape').waitFor();await drag(tile(49,49),tile(51,51));await button('Apply shape').click();doc=await save();
  assert.equal(doc.source.allowed_mask[50][50],'1');assert.equal(doc.source.allowed_mask[40][40],'0');assert.equal(doc.source.allowed_mask[149],'1'.repeat(150));
  await button('Undo stroke (Ctrl+Z)').click();await save();
  await page.getByRole('button',{name:/Shape tools/}).click();await page.getByRole('menuitem',{name:'Ellipse preset',exact:true}).click();await button('Add shape').click();await page.getByRole('menuitem',{name:'Replace shape',exact:true}).click();await drag(tile(10,10),tile(130,130));await button('Apply shape').waitFor();
  assert.equal(await saveDisabled(),'true');
  await button('Cancel shape').click();doc=await save();assert.equal(doc.source.allowed_mask[50][50],'0');
  await drag(tile(10,10),tile(130,130));await button('Apply shape').click();doc=await save();
  assert.equal(doc.source.allowed_mask[70][70],'1');assert.equal(doc.source.allowed_mask[10][10],'0');assert.equal(doc.source.allowed_mask[0],'0'.repeat(150));
  const ellipse=doc.source.allowed_mask;
  await page.getByRole('button',{name:/Shape tools/}).click();await page.getByRole('menuitem',{name:'L-shape preset',exact:true}).click();await drag(tile(20,20),tile(110,110));await button('Apply shape').click();doc=await save();
  assert.equal(doc.source.allowed_mask[25][100],'0');assert.equal(doc.source.allowed_mask[100][100],'1');
  await button('Undo stroke (Ctrl+Z)').click();doc=await save();assert.deepEqual(doc.source.allowed_mask,ellipse);
  await page.getByRole('button',{name:/Fill tools/}).click();await page.getByRole('menuitem',{name:'Clear connected area',exact:true}).click();await click(tile(70,70));doc=await save();assert.equal(doc.source.allowed_mask.join(''),'0'.repeat(22500));
  await button('Paint allowed tiles').click();await drag(tile(0,149),tile(149,149));doc=await save();assert.equal(doc.source.allowed_mask[149],'1'.repeat(150));
  await page.getByRole('button',{name:/Fill tools/}).click();await page.getByRole('menuitem',{name:'Fill connected area',exact:true}).click();await click(tile(0,0));doc=await save();assert.equal(doc.source.allowed_mask.join(''),'1'.repeat(22500));
  // Resize must require explicit crop consent; expanding pads with disallowed tiles.
  const resize=async(n,crop=false)=>{await button('Resize canvas').click();await page.getByRole('textbox',{name:'Columns (1–512)',exact:true}).fill('');await page.getByRole('textbox',{name:'Columns (1–512)',exact:true}).fill(''+n);await page.getByRole('textbox',{name:'Rows (1–512)',exact:true}).fill('');await page.getByRole('textbox',{name:'Rows (1–512)',exact:true}).fill(''+n);if(crop)await page.getByRole('checkbox').click();await button('Resize').click();};
  await resize(100);await text(/Resize would crop allowed tiles/).waitFor();doc=await save();assert.equal(doc.source.settings.columns,150);
  await resize(100,true);doc=await save();assert.equal(doc.source.settings.columns,100);
  await button('Undo stroke (Ctrl+Z)').click();doc=await save();assert.equal(doc.source.settings.columns,150);
  await resize(512);doc=await save();assert.equal(doc.source.settings.columns,512);assert.equal(doc.source.allowed_mask[511],'0'.repeat(512));
  tile=await fit(512);await button('Paint allowed tiles').click();
  const times=[];
  for(let i=0;i<5;i++){const start=Date.now();await drag(tile(180,180+i*2),tile(400,180+i*2));await save();times.push(Date.now()-start);}
  doc=await save();assert.equal(doc.source.allowed_mask[180].slice(180,401),'1'.repeat(221));
  await button('Canvas layers').click();await page.getByRole('menuitemcheckbox',{name:'Detached / narrow / rejected tiles'}).click();
  await button('Switch to dark mode').click();await button('Switch to light mode').waitFor();assert.equal(await page.evaluate(()=>localStorage.getItem('dungeon.theme')),'dark');
  await page.screenshot({path:path.join(output,'phase10-dark.png')});
  await button('Switch to light mode').click();await page.screenshot({path:path.join(output,'phase10-light.png')});
  // Reopen edited source, retain exact shape, and validate source-room rejection.
  await page.evaluate(s=>{pickText=s;},JSON.stringify(doc));await fileCommand('open');await text('Opened canvas.json.').waitFor();assert.deepEqual((await save()).source.allowed_mask,doc.source.allowed_mask);
  let fixed=structuredClone(original);fixed.source.rooms=[{id:'fixed',name:'Sanctum',bounds:{x:20,y:20,width:10,height:10},role:'normal',tags:[],lock_position:true,lock_size:true,capacity_override:null}];
  await page.evaluate(s=>{pickText=s;},JSON.stringify(fixed));await fileCommand('open');await page.waitForTimeout(200);tile=await fit();
  await button('Erase allowed tiles').click();await click(tile(20,20));await page.waitForTimeout(200);doc=await save();assert.equal(doc.source.allowed_mask[20][20],'1');assert.equal(doc.source.rooms[0].lock_position,true);
  await button('Switch to dark mode').click();await page.reload();await enable();await button('Switch to light mode').waitFor();
  await page.setViewportSize({width:520,height:800});await page.screenshot({path:path.join(output,'phase10-compact.png')});
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(output,'phase10-browser-metrics.json'),JSON.stringify({canvas:512,dpi:2,gestureAndConfirmedSaveMs:times,chrome:browser.version()},null,2));
  console.log('PASS Phase 10: precise edges/DPR2/zoom, interpolated strokes, undo/redo, preview/cancel/apply, ellipse/L, fill, crop/resize, 512 canvas, protected rooms, persistence and both themes. Gesture + saved source ms:',times);
 } catch(e){if(page){await page.screenshot({path:path.join(output,'phase10-failure.png')});fs.writeFileSync(path.join(output,'phase10-failure.html'),await page.locator('flt-semantics-host').innerHTML());}throw e;}
 finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});

