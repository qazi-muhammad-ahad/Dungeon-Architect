// Real Flutter UI + C++ Wasm: source authoring, catalogue, allocation reuse and files.
const {chromium} = require('playwright');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../apps/flutter_ui/build/web');
const output = path.resolve(__dirname, '../../output/app');
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost').pathname;
  const file = path.resolve(root, '.' + (url === '/' ? '/index.html' : decodeURIComponent(url)));
  if (!file.startsWith(root + path.sep)) return res.writeHead(404).end();
  fs.readFile(file, (error, data) => {
    if (error) return res.writeHead(404).end();
    res.writeHead(200, {'Content-Type': ({'.js':'text/javascript', '.wasm':'application/wasm', '.html':'text/html', '.json':'application/json', '.ttf':'font/ttf'})[path.extname(file)] || 'application/octet-stream'}).end(data);
  });
});

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({channel:'chrome', headless:true});
  let page;
  try {
    fs.mkdirSync(output, {recursive:true});
    page = await browser.newPage({viewport:{width:1600, height:1100}, reducedMotion:'reduce'});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      globalThis.written = null;
      globalThis.pickText = '';
      const handle = {
        name:'phase11.json',
        getFile:async () => new File([pickText], 'phase11.json'),
        createWritable:async () => ({write:async value => {written=value;}, close:async () => {}, abort:async () => {}}),
      };
      globalThis.showSaveFilePicker = async () => handle;
      globalThis.showOpenFilePicker = async () => [handle];
    });
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    const semantics = page.locator('flt-semantics-placeholder');
    await semantics.waitFor(); await semantics.evaluate(node => node.click());
    const button = name => page.getByRole('button', {name, exact:true});
    const text = value => page.getByText(value).or(page.getByLabel(value)).first();
    const fileCommand = async command => {
      await page.getByRole('button', {name:/Project commands/}).click();
      await page.getByRole('menuitem', {name:command === 'save' ? /^Save\s+Ctrl\+S/ : /^Open…/}).click();
    };
    const save = async () => {
      await page.evaluate(() => {written=null;});
      await fileCommand('save');
      await page.waitForFunction(() => written !== null);
      await text('All source changes saved').waitFor();
      return JSON.parse(await page.evaluate(() => written));
    };
    // Flutter's scrollable inspector only exposes visible semantics nodes.
    const inspectorTop = async () => {
      await page.mouse.move(1510, 430); await page.mouse.wheel(0, -5000);
      await page.waitForTimeout(120);
    };
    const reveal = async locator => {
      for (let i=0; i<24; ++i) {
        if (await locator.count() && await locator.isVisible()) return locator;
        await page.mouse.move(1510, 650); await page.mouse.wheel(0, 350);
        await page.waitForTimeout(80);
      }
      await locator.waitFor({timeout:1500}); return locator;
    };
    const canvas = page.getByLabel('Design tile canvas. Wheel zooms; Space or middle drag pans. Use toolbar tools to edit.', {exact:true});
    const fit = async () => {
      await button('Fit canvas (F)').click();
      const box = await canvas.boundingBox(); assert.ok(box);
      const scale = Math.min((box.width-48)/150, (box.height-48)/150);
      return (x,y) => ({x:box.x+(box.width-150*scale)/2+(x+.5)*scale, y:box.y+(box.height-150*scale)/2+(y+.5)*scale});
    };
    const drag = async (a,b) => {
      await page.mouse.move(a.x,a.y); await page.mouse.down();
      await page.mouse.move(b.x,b.y,{steps:3}); await page.mouse.up();
    };
    const roomTool = async name => {
      await page.getByRole('button', {name:/Room tools/}).click();
      await page.getByRole('menuitem', {name, exact:true}).click();
    };
    await button('Generate & solve').waitFor();
    await page.waitForFunction(() => [...document.querySelectorAll('[role=button]')].some(node => node.textContent === 'Generate & solve' && node.getAttribute('aria-disabled') !== 'true'));
    await save();
    let tile = await fit();
    // Draw the allowed area, then explicitly preview/apply a fixed source room.
    await page.getByRole('button', {name:/Shape tools/}).click();
    await page.getByRole('menuitem', {name:'Rectangle preset', exact:true}).click();
    await button('Add shape').click();
    await page.getByRole('menuitem', {name:'Replace shape', exact:true}).click();
    await drag(tile(5,5), tile(144,144)); await button('Apply shape').click();
    let doc = await save();
    assert.equal(doc.source.allowed_mask[0], '0'.repeat(150));
    assert.equal(doc.source.allowed_mask[75].slice(5,145), '1'.repeat(140));
    await roomTool('Draw fixed room'); await drag(tile(20,20), tile(31,31));
    await button('Apply room').waitFor();
    // Native preview is a draft: Save must be disabled until explicit commit.
    await page.getByRole('button', {name:/Project commands/}).click();
    assert.equal(await page.getByRole('menuitem', {name:/^Save\s+Ctrl\+S/}).getAttribute('aria-disabled'), 'true');
    await page.keyboard.press('Escape'); await button('Apply room').click();
    doc = await save();
    const fixed = doc.source.rooms.find(room => room.id === 'room-1');
    assert.ok(fixed); assert.equal(fixed.lock_position, true); assert.equal(fixed.lock_size, true);
    assert.deepEqual(fixed.bounds, {x:20,y:20,width:12,height:12});
    await roomTool('Move unlocked room'); await drag(tile(25,25), tile(28,27));
    await text(/Unlock room explicitly/).waitFor();
    assert.deepEqual((await save()).source.rooms.find(room => room.id==='room-1').bounds, fixed.bounds);
    // A separate unlock transaction is required before the move preview.
    await inspectorTop(); await (await reveal(button('Unlock room'))).click();
    await save(); await drag(tile(25,25), tile(28,27)); await button('Apply room').click();
    doc = await save();
    const moved = doc.source.rooms.find(room => room.id==='room-1');
    assert.deepEqual(moved.bounds, {x:23,y:22,width:12,height:12});
    assert.equal(moved.lock_position, true);
    // A new Draw gesture must not reuse the preceding Move room's ID or locks.
    await roomTool('Draw fixed room'); await drag(tile(50,50), tile(61,61));
    await button('Apply room').waitFor(); await button('Cancel room').click();
    assert.deepEqual((await save()).source.rooms, doc.source.rooms);
    await button('Generate & solve').click(); await text(/Completed\. Exact allocation verified/).waitFor({timeout:45000});
    await text('VERIFIED').waitFor();
    doc = await save();
    assert.deepEqual(doc.source.rooms.find(room => room.id==='room-1').bounds, moved.bounds);
    // Edit the saved catalogue without changing the generated dungeon.
    await inspectorTop(); await (await reveal(button('New pack'))).click();
    const dialog = page.getByRole('alertdialog');
    const enter = async (label, value) => {
      const input = dialog.getByRole('textbox', {name:label, exact:true});
      await input.click(); await page.keyboard.press('Control+A');
      await page.keyboard.insertText(value);
      assert.equal(await input.inputValue(),value);
      await page.waitForTimeout(70);
    };
    await enter('Pack name', 'Phase 11 patrol');
    await enter('Slots (spawn positions)', '0');
    await button('Save pack').click(); await text(/positive whole number/).waitFor();
    await enter('Slots (spawn positions)', '1');
    await enter('Threat (points)', '0');
    await enter('Designer score (points)', '100');
    await button('Save pack').click(); await dialog.waitFor({state:'hidden'});
    doc = await save();
    assert.equal(doc.source.packs.length,1);
    assert.equal(doc.source.packs[0].score,100);
    assert.equal(doc.source.packs[0].active,true);
    await button('Optimize').first().click(); await text(/Completed\. Geometry reused; exact allocation verified/).waitFor({timeout:30000});
    await text('VERIFIED').waitFor();
    await inspectorTop(); await (await reveal(button('Duplicate pack'))).click();
    doc = await save();
    assert.equal(doc.source.packs.length,2);
    assert.equal(new Set(doc.source.packs.map(pack => pack.id)).size,2);
    // Deactivate the duplicate while preserving it in the catalogue.
    await inspectorTop(); const editButtons = page.getByRole('button', {name:'Edit pack', exact:true});
    await reveal(editButtons.first());
    await editButtons.last().click();
    await dialog.getByRole('switch', {name:/Active inventory/}).click();
    await button('Save pack').click(); await dialog.waitFor({state:'hidden'});
    doc = await save();
    assert.equal(doc.source.packs.filter(pack => pack.active).length,1);
    const saved = JSON.stringify(doc);
    await page.evaluate(value => {pickText=value;},saved); await fileCommand('open');
    await text('Opened phase11.json.').waitFor();
    assert.deepEqual(await save(), doc);
    await button('Generate & solve').click(); await text(/Completed\. Exact allocation verified/).waitFor({timeout:45000});
    await page.screenshot({path:path.join(output,'phase11-workflow.png')});
    assert.deepEqual(errors,[],'No unhandled browser errors');
    console.log('PASS Phase 11 real-engine workflow: draw mask, preview/fix/move with explicit unlock, generate, invalid pack recovery, create/duplicate/deactivate catalogue, reuse geometry, save and reopen.');
  } catch (error) {
    if (page) {
      try {
        await page.screenshot({path:path.join(output,'phase11-failure.png'), timeout:3000});
        const host = page.locator('flt-semantics-host');
        fs.writeFileSync(path.join(output,'phase11-failure.html'), await host.count()
          ? await host.innerHTML({timeout:1500}) : await page.content());
      } catch (captureError) { console.error('Could not capture failure artifacts:', captureError.message); }
    }
    throw error;
  } finally {await browser.close(); server.close();}
})().catch(error => {console.error(error); server.close(); process.exitCode=1;});
