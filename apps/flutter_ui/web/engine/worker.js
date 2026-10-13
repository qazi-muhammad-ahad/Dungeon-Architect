/* Dedicated worker: only this file owns the Wasm instance and native handles. */
'use strict';
let engine, context = 0, job = 0, executing = false, closed = false;
const decoder = new TextDecoder('utf-8', {fatal: true});
const statuses = ['ok','invalid_argument','invalid_handle','busy','version_mismatch','buffer_too_small','not_ready','resource_failure','internal_error','stale_result'];
function check(status) {
  if (status !== 0) throw Object.assign(new Error(`Engine API: ${statuses[status] || status}`), {code: statuses[status] || 'api_error'});
}
function alloc(length) {
  const p = engine._malloc(length);
  if (!p) throw Object.assign(new Error('The engine could not allocate memory.'), {code: 'resource_failure'});
  return p;
}
function bytes(fn) {
  const length = alloc(4); let buffer = 0;
  try {
    const status = fn(0, 0, length);
    if (status !== 5 && status !== 0) check(status);
    const size = engine.HEAPU32[length >>> 2];
    if (size > 128 * 1024 * 1024) throw new Error('Engine report exceeds the byte limit.');
    if (!size) return '';
    buffer = alloc(size); check(fn(buffer, size, length));
    return decoder.decode(engine.HEAPU8.subarray(buffer, buffer + size));
  } finally { if (buffer) engine._free(buffer); engine._free(length); }
}
function poll() {
  if (!job) return {state: 0, stage: 0, outcome: 0};
  const p = alloc(12);
  try {
    check(engine._da_job_poll(job,p,p+4,p+8));
    return {state:engine.HEAPU32[p>>>2], stage:engine.HEAPU32[(p+4)>>>2], outcome:engine.HEAPU32[(p+8)>>>2]};
  } finally { engine._free(p); }
}
function dispose() {
  if (job) { check(engine._da_job_release(job)); job = 0; }
  if (context) { check(engine._da_context_release(context)); context = 0; }
  closed = true;
}
async function handle(message) {
  const {type, data = {}} = message;
  if (type === 'init') {
    if (engine || closed) throw new Error('Worker already initialized or closed.');
    try {
      importScripts('dungeon_engine.js');
      engine = await createDungeonEngine({locateFile: name => new URL(name,self.location.href).href});
    } catch (error) {
      throw Object.assign(new Error(`Cannot load the C++ WebAssembly engine. Build tools/build-web-engine.ps1 and serve its JS/Wasm assets over HTTP. ${error.message}`), {code:'engine_load_failed'});
    }
    if (engine._da_bootstrap_abi_version() !== 1 || engine._da_pointer_bits() !== 32)
      throw Object.assign(new Error('Incompatible engine ABI or Wasm architecture. Rebuild the app and engine together.'), {code:'version_mismatch'});
    const p = alloc(4);
    try { check(engine._da_context_create(data.abi ?? 1,data.schema ?? 1,p)); context = engine.HEAPU32[p>>>2]; }
    finally { engine._free(p); }
    return {abi:1,schema:1,pointerBits:32};
  }
  if (!context || closed) throw Object.assign(new Error('Engine is not open.'), {code:'closed'});
  if (type === 'cancel') { if (job) check(engine._da_job_cancel(job)); return null; }
  if (type === 'poll') return poll();
  if (executing) throw Object.assign(new Error('An engine job is already running.'), {code:'busy'});
  if (type === 'run') {
    if (typeof data.project !== 'string') throw new Error('Project must be raw UTF-8 JSON text.');
    const input = new TextEncoder().encode(data.project);
    if (input.length === 0 || input.length > 16*1024*1024) throw Object.assign(new Error('Project must be 1–16777216 UTF-8 bytes.'), {code:'invalid_argument'});
    if (job) { check(engine._da_job_release(job)); job = 0; }
    let p = 0, out = 0;
    try {
      p = alloc(input.length); out = alloc(4);
      engine.HEAPU8.set(input,p);
      check(engine._da_job_create(context,data.operation,p,input.length,data.events,data.flags,out));
      job = engine.HEAPU32[out>>>2];
    } finally { if (out) engine._free(out); if (p) engine._free(p); }
    executing = true;
    self.postMessage({type:'progress', value:{state:1,stage:1,outcome:0}});
    let previous = '';
    const timer = setInterval(() => {
      const value = poll(), key = JSON.stringify(value);
      if (key !== previous) { previous = key; self.postMessage({type:'progress',value}); }
    },40);
    try {
      const status = await engine.ccall('da_job_execute','number',['number'],[job],{async:true});
      if (status !== 0 && status !== 7 && status !== 8) check(status);
      const report = bytes((p,n,out) => engine._da_job_read(job,1,p,n,out));
      self.postMessage({type:'progress',value:poll()});
      return {report, snapshotJob:job, outcome:poll().outcome};
    } finally { executing = false; clearInterval(timer); }
  }
  if (type === 'metrics') return bytes((p,n,out) => engine._da_job_read(job,2,p,n,out));
  if (type === 'trace') return bytes((p,n,out) => engine._da_job_trace(job,data.cursor,data.count,p,n,out));
  if (type === 'last') return bytes((p,n,out) => engine._da_context_read(context,p,n,out));
  if (type === 'step') {
    const p = alloc(8);
    try {
      check(engine._da_context_step(context,data.snapshotJob,data.x,data.y,data.dx,data.dy,p,p+4));
      return {x:engine.HEAP32[p>>>2],y:engine.HEAP32[(p+4)>>>2]};
    } finally { engine._free(p); }
  }
  if (type === 'close') { dispose(); return null; }
  throw Object.assign(new Error('Unknown worker operation.'), {code:'invalid_argument'});
}
self.onmessage = async event => {
  const {id} = event.data;
  try { self.postMessage({id,ok:true,value:await handle(event.data)}); }
  catch (error) { self.postMessage({id,ok:false,error:{code:error.code || 'worker_error',message:error.message || String(error)}}); }
};
