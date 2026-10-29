// Usage: node tests/web/phase17_package_test.cjs "<relocated package>" [--browser]
// Tests the actual portable binaries/assets; never serves replacement assets.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const net = require('node:net');
const crypto = require('node:crypto');
const {spawn, spawnSync} = require('node:child_process');
const pkg = path.resolve(process.argv[2] || '');
assert.ok(process.argv[2], 'Supply an extracted package directory');
const cwd = fs.mkdtempSync(path.join(path.dirname(pkg), 'Dungeon Architect independent cwd '));
const cleanEnv = {...process.env, PATH:process.env.SystemRoot + '\\System32'};
const run = (exe,args,expected=0) => {
  const result = spawnSync(path.join(pkg,exe),args,{cwd,env:cleanEnv,windowsHide:true,encoding:'utf8',timeout:60000,maxBuffer:32*1024*1024});
  assert.equal(result.status,expected,`${exe} ${args.join(' ')}: ${result.error || result.stderr || result.stdout}`);
  return result.stdout;
};
function imports(file) {
  const b=fs.readFileSync(file), pe=b.readUInt32LE(0x3c), count=b.readUInt16LE(pe+6), optional=pe+24;
  assert.equal(b.toString('ascii',pe,pe+4),'PE\0\0');
  assert.equal(b.readUInt16LE(pe+4),0x8664,'Native package must be x64');
  const directory=optional+(b.readUInt16LE(optional)===0x20b?112:96), sections=optional+b.readUInt16LE(pe+20);
  const offset=rva=>{
    for(let i=0;i<count;i++) {
      const s=sections+40*i, va=b.readUInt32LE(s+12), size=Math.max(b.readUInt32LE(s+8),b.readUInt32LE(s+16));
      if(rva>=va&&rva<va+size) return b.readUInt32LE(s+20)+rva-va;
    }
    throw Error(`Unmapped PE RVA ${rva} in ${path.basename(file)}`);
  };
  const rva=b.readUInt32LE(directory+8); if(!rva) return [];
  const names=[];
  for(let i=offset(rva);b.readUInt32LE(i+12);i+=20) {
    const start=offset(b.readUInt32LE(i+12)); names.push(b.toString('ascii',start,b.indexOf(0,start)));
  }
  return names;
}
function closure() {
  const pending=['dungeon_launcher.exe','bin/dungeon_cli.exe','bin/dungeon_api_caller.exe','bin/libdungeon_api.dll'], seen=new Set(), evidence={};
  while(pending.length) {
    const relative=pending.pop(); if(seen.has(relative)) continue; seen.add(relative);
    const file=path.join(pkg,relative), dependencies=imports(file); evidence[relative]=dependencies;
    for(const name of dependencies) {
      const local=path.join(path.dirname(relative),name);
      if(fs.existsSync(path.join(pkg,local))) pending.push(local);
      else assert.ok(/^(api-ms-win-|ext-ms-win-)/i.test(name)||fs.existsSync(path.join(process.env.SystemRoot,'System32',name)),`Unbundled non-system dependency ${name} (${relative})`);
    }
  }
  return evidence;
}
const request=(port,target,method='GET',host=`127.0.0.1:${port}`)=>new Promise((resolve,reject)=>{
  const req=http.request({hostname:'127.0.0.1',port,path:target,method,headers:{Host:host},timeout:5000},res=>{
    const chunks=[];res.on('data',x=>chunks.push(x));res.on('end',()=>resolve({status:res.statusCode,headers:res.headers,body:Buffer.concat(chunks)}));
  });req.on('error',reject);req.on('timeout',()=>req.destroy(Error('HTTP request timeout')));req.end();
});
const raw=(port,data,timeout=8000)=>new Promise((resolve,reject)=>{
  const socket=net.connect(port,'127.0.0.1',()=>socket.write(data));let response='';
  socket.setTimeout(timeout,()=>socket.destroy(Error('Server did not bound malformed/incomplete request')));
  socket.on('data',x=>response+=x);socket.on('error',error=>error.code==='ECONNRESET'?resolve(response):reject(error));socket.on('close',()=>resolve(response));
});
(async()=>{
  let server;
  try {
    const manifest=JSON.parse(fs.readFileSync(path.join(pkg,'package-manifest.json'),'utf8').replace(/^\uFEFF/,''));
    assert.equal(manifest.format,1);assert.equal(manifest.abi,1);
    const listed=new Set();
    for(const entry of manifest.files) {
      assert.ok(!entry.path.includes('..')&&!path.isAbsolute(entry.path),'Manifest paths are relative');
      const bytes=fs.readFileSync(path.join(pkg,entry.path));listed.add(entry.path);
      assert.equal(bytes.length,entry.bytes);assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),entry.sha256);
    }
    const actual=[];(function walk(dir){for(const item of fs.readdirSync(dir,{withFileTypes:true})){const f=path.join(dir,item.name);if(item.isDirectory())walk(f);else actual.push(path.relative(pkg,f).replaceAll('\\','/'));}})(pkg);
    assert.deepEqual(actual.filter(p=>p!=='package-manifest.json').sort(),[...listed].sort(),'Manifest covers exact package contents');
    for(const required of ['api/example.c','api/include/dungeon_architect_c.h','api/lib/libdungeon_api.dll.a','START-HERE.md','licenses/THIRD-PARTY-NOTICES.md','licenses/Flutter-runtime-NOTICES'])assert.ok(listed.has(required),required);
    const dependencyClosure=closure();
    const cli='bin/dungeon_cli.exe', sample=path.join(pkg,'samples/teaching.json');
    run(cli,['--version']);
    for(const name of ['blank.json','teaching.json','irregular-fortress.json']) run(cli,['validate',path.join(pkg,'samples',name),'--json']);
    const baseline=JSON.parse(run(cli,['run',sample,'--json','--events','3']));
    assert.equal(baseline.outcome,'success');assert.equal(baseline.result.allocation.total_score,14);
    const saved=path.join(cwd,'saved project.json');run(cli,['save',sample,saved,'--json']);
    assert.deepEqual(JSON.parse(run(cli,['run',saved,'--json','--events','3'])).result,baseline.result);
    const example=JSON.parse(run('bin/dungeon_api_caller.exe',[sample,'5']));
    assert.deepEqual(example.result,baseline.result,'Standalone C caller and CLI share authoritative output');
    const source=JSON.parse(fs.readFileSync(sample,'utf8')), first=source.source.packs[0];
    source.source.packs=Array.from({length:15},(_,i)=>({...first,id:`package-limit-${i}`,active:true}));
    const unsupported=path.join(cwd,'unsupported.json');fs.writeFileSync(unsupported,JSON.stringify(source));
    const oversized=JSON.parse(run(cli,['run',unsupported,'--json'],3));assert.equal(oversized.outcome,'unsupported_size');
    const cancel=path.join(cwd,'cancel.flag');fs.writeFileSync(cancel,'cancel');
    assert.equal(JSON.parse(run(cli,['run',sample,'--json','--cancel-file',cancel],6)).outcome,'cancelled');
    run('dungeon_launcher.exe',['--port','65536','--no-browser'],2);
    server=spawn(path.join(pkg,'dungeon_launcher.exe'),['--port','0','--no-browser'],{cwd,env:cleanEnv,windowsHide:true,stdio:['ignore','pipe','pipe']});
    const base=await new Promise((resolve,reject)=>{
      let output='';const timer=setTimeout(()=>reject(Error(`Launcher startup timeout: ${output}`)),10000);
      server.stdout.on('data',chunk=>{output+=chunk;const m=/http:\/\/127\.0\.0\.1:(\d+)\//.exec(output);if(m){clearTimeout(timer);resolve(m[0].replace(/\/$/,''));}});
      server.once('error',reject);server.once('exit',code=>{clearTimeout(timer);reject(Error(`Launcher exited ${code}: ${output}`));});
    });
    const port=Number(new URL(base).port), index=await request(port,'/');assert.equal(index.status,200);
    run('dungeon_launcher.exe',['--port',String(port),'--no-browser'],1);
    assert.equal((await request(port,'/')).status,200,'Port conflict leaves original host running');
    for(const [key,value] of Object.entries({'x-content-type-options':'nosniff','x-frame-options':'DENY','referrer-policy':'no-referrer','cross-origin-opener-policy':'same-origin','cross-origin-resource-policy':'same-origin','cache-control':'no-store'})) assert.equal(index.headers[key],value);
    assert.ok(index.headers['content-security-policy'].includes("default-src 'none'"));
    assert.ok(index.headers['content-security-policy'].includes("script-src 'self' 'wasm-unsafe-eval'"));
    const head=await request(port,'/','HEAD');assert.equal(head.status,200);assert.equal(head.body.length,0);assert.equal(head.headers['content-length'],String(index.body.length));
    const wasm=(function find(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,entry.name);if(entry.isDirectory()){const found=find(p);if(found)return found;}else if(p.endsWith('.wasm'))return p;}})(path.join(pkg,'web'));
    assert.ok(wasm);const asset=await request(port,'/'+path.relative(path.join(pkg,'web'),wasm).replaceAll('\\','/'));assert.equal(asset.status,200);assert.equal(asset.headers['content-type'],'application/wasm');assert.deepEqual(asset.body,fs.readFileSync(wasm));
    for(const target of ['/../package-manifest.json','/%2e%2e/package-manifest.json','/%2e%2e%5cpackage-manifest.json','/index.html:secret','/index.html%00','/%GG','/engine/','/api/run','/.env','/samples/teaching.json','/bin/libdungeon_api.dll']) assert.ok([400,403,404].includes((await request(port,target)).status),`Unsafe target ${target}`);
    for(const method of ['POST','PUT','DELETE','OPTIONS']) {const response=await request(port,'/',method);assert.equal(response.status,405);assert.equal(response.headers.allow,'GET, HEAD');}
    assert.ok([400,403].includes((await request(port,'/','GET','evil.invalid')).status),'Host rebinding rejected');
    // Controlled junction into a sibling directory; remove only the link itself.
    const target=fs.mkdtempSync(path.join(path.dirname(pkg),'phase17 escape target ')),link=path.join(pkg,'web','__phase17_escape__');
    assert.ok(fs.realpathSync(target).startsWith(fs.realpathSync(path.dirname(pkg))+path.sep));
    try {
      fs.writeFileSync(path.join(target,'private.txt'),'outside web sentinel');
      fs.symlinkSync(target,link,'junction');assert.equal(fs.realpathSync(link),fs.realpathSync(target));
      assert.equal((await request(port,'/__phase17_escape__/private.txt')).status,404,'Reparse point escape blocked');
    } finally {
      if(fs.existsSync(link)){assert.equal(fs.realpathSync(link),fs.realpathSync(target));fs.rmdirSync(link);}
      fs.unlinkSync(path.join(target,'private.txt'));fs.rmdirSync(target);
    }
    assert.ok(!/^HTTP\/1\.1 200/.test(await raw(port,`GET / HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nX-Pad: `+ 'x'.repeat(20000)+'\r\n\r\n')));
    assert.ok(!/^HTTP\/1\.1 200/.test(await raw(port,`GET / HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\n`)));
    assert.equal((await request(port,'/')).status,200,'Malformed client cannot poison subsequent requests');
    console.log(JSON.stringify({checks:'relocated package, different cwd, sanitized PATH, x64 DLL closure, samples/save/replay, standalone C ABI, oversize/cancel, read-only loopback HTTP, traversal/method/Host/headers/MIME/bounded-client recovery',dependencyClosure,base}));
    if(process.argv.includes('--browser')) {
      for(const name of ['phase12_13_test.cjs','phase14_15_test.cjs','phase17_browser_test.cjs']) {
        const child=spawn(process.execPath,[path.join(__dirname,name)],{cwd,windowsHide:true,env:{...process.env,DA_TEST_BASE_URL:base,DA_TEST_PACKAGE:pkg},stdio:'inherit'});
        const status=await new Promise(resolve=>child.once('exit',resolve));assert.equal(status,0,`${name} packaged browser workflow`);
      }
    }
  } finally {
    if(server&&server.exitCode===null&&server.signalCode===null) {const exited=new Promise(resolve=>server.once('exit',resolve));server.kill();await exited;}
    fs.rmSync(cwd,{recursive:true,force:true});
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
