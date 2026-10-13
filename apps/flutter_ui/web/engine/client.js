/* Public browser adapter. No engine rules live in JavaScript. */
(function(root) {
  'use strict';
  // Never round engine int64 values on the way to Dart web. Raw report text is
  // also retained, so exporting it preserves the canonical numeric JSON tokens.
  function safeJson(text) {
    return JSON.stringify(JSON.parse(text, (key,value,context) => {
      if (typeof value === 'number' && !Number.isSafeInteger(value)) {
        if (!context || !context.source) throw new Error('This browser cannot preserve 64-bit engine integers. Use a current Chrome version.');
        return context.source;
      }
      return value;
    }));
  }
  class DungeonEngineClient {
    constructor(options = {}) {
      this.closed = false; this.closing = false; this.next = 1; this.pending = new Map();
      this.lastResult = null; this.snapshotJob = 0; this.progressJson = '{"state":0,"stage":0,"outcome":0}';
      this.running = null;
      this.worker = new Worker(options.workerUrl || new URL('engine/worker.js',document.baseURI));
      this.worker.onmessage = ({data}) => {
        if (this.closed) return;
        if (data.type === 'progress') { this.progressJson = JSON.stringify(data.value); return; }
        const pending = this.pending.get(data.id);
        if (!pending) return;
        this.pending.delete(data.id);
        if (data.ok) pending.resolve(data.value);
        else pending.reject(Object.assign(new Error(data.error.message),{code:data.error.code}));
      };
      this.worker.onerror = event => {
        event.preventDefault();
        this.abort(Object.assign(new Error('Engine worker failed to load or crashed. Check the JS/Wasm assets and HTTP server.'),{code:'engine_load_failed'}));
      };
      this.unload = () => this.abort(Object.assign(new Error('Page closed.'),{code:'closed'}));
      root.addEventListener('pagehide',this.unload);
      this.ready = this.request('init',{abi:options.abi ?? 1,schema:options.schema ?? 1});
      this.loadTimer = setTimeout(() => this.abort(Object.assign(new Error('Engine loading timed out. Check the JS/Wasm assets.'),{code:'engine_load_failed'})),30000);
      this.ready.then(() => clearTimeout(this.loadTimer), error => { clearTimeout(this.loadTimer); this.abort(error); });
    }
    request(type,data = {}) {
      if (this.closed) return Promise.reject(Object.assign(new Error('Engine is closed.'),{code:'closed'}));
      const id = this.next++;
      return new Promise((resolve,reject) => {
        this.pending.set(id,{resolve,reject});
        try { this.worker.postMessage({id,type,data}); }
        catch(error) { this.pending.delete(id); reject(error); }
      });
    }
    async run(project,operation = 5,events = 256,flags = 0) {
      if (this.closed || this.closing) throw Object.assign(new Error('Engine is closed.'),{code:'closed'});
      if (this.running) throw Object.assign(new Error('An engine job is already running.'),{code:'busy'});
      if (![operation,events,flags].every(Number.isInteger) || operation < 1 || operation > 8 || events < 0 || events > 4096 || flags < 0 || flags > 1)
        throw Object.assign(new Error('Invalid operation, event limit or flags.'),{code:'invalid_argument'});
      this.running = (async () => {
        await this.ready;
        if (this.closing) throw Object.assign(new Error('Engine is closing.'),{code:'closed'});
        const value = await this.request('run',{project,operation,events,flags});
        if (value.outcome === 0 && operation >= 2 && operation <= 5) { this.lastResult = value.report; this.snapshotJob = value.snapshotJob; }
        return value.report;
      })();
      try { return await this.running; } finally { this.running = null; }
    }
    async cancel() { await this.ready; if (!this.closed) await this.request('cancel'); }
    async metrics() { await this.ready; return this.request('metrics'); }
    async trace(cursor = 0,count = 128) {
      if (!Number.isInteger(cursor) || cursor < 0 || cursor > 0xffffffff || !Number.isInteger(count) || count < 1 || count > 128)
        throw Object.assign(new Error('Trace cursor/count outside the contract.'),{code:'invalid_argument'});
      await this.ready; return this.request('trace',{cursor,count});
    }
    async step(snapshotJob,x,y,dx,dy) {
      if (![snapshotJob,x,y,dx,dy].every(Number.isInteger) || snapshotJob < 1 || snapshotJob > 0xffffffff ||
          [x,y,dx,dy].some(n => n < -2147483648 || n > 2147483647)) throw new Error('Step arguments exceed fixed-width integer limits.');
      await this.ready; return JSON.stringify(await this.request('step',{snapshotJob,x,y,dx,dy}));
    }
    async close() {
      if (this.closed) return;
      if (this.closePromise) return this.closePromise;
      this.closing = true;
      this.closePromise = (async () => {
        // Cooperative cleanup first; termination bounds close even for a bad load
        // or a stalled Wasm instance. No worker references survive page close.
        const timer = setTimeout(() => this.abort(Object.assign(new Error('Engine closed.'),{code:'closed'})),2000);
        try {
          await this.ready;
          await this.cancel();
          if (this.running) await this.running.catch(() => {});
          if (!this.closed) await this.request('close');
        } catch (_) { /* abort below owns outstanding resources */ }
        finally { clearTimeout(timer); this.abort(Object.assign(new Error('Engine closed.'),{code:'closed'})); }
      })();
      return this.closePromise;
    }
    abort(error) {
      if (this.closed) return;
      this.closed = true; clearTimeout(this.loadTimer);
      this.worker.terminate(); this.worker.onmessage = null; this.worker.onerror = null;
      root.removeEventListener('pagehide',this.unload);
      for (const pending of this.pending.values()) pending.reject(error);
      this.pending.clear();
    }
    static safeJson(text) { return safeJson(text); }
  }
  root.DungeonEngineClient = DungeonEngineClient;
})(globalThis);

