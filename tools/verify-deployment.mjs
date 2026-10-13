import assert from 'node:assert/strict';
import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'apps/flutter_ui/build/web');
const config = JSON.parse(await readFile(path.join(root, 'vercel.json'), 'utf8'));
assert.equal(config.outputDirectory, 'apps/flutter_ui/build/web');
assert.equal(config.framework, null);
assert.ok(!config.functions && !config.rewrites, 'No server functions or catch-all API rewrites');
for (const file of ['index.html', 'flutter_bootstrap.js', 'main.dart.js', 'engine/client.js', 'engine/files.js', 'engine/worker.js', 'engine/dungeon_engine.js', 'engine/dungeon_engine.wasm', 'canvaskit/canvaskit.wasm']) {
  assert.ok((await stat(path.join(output, file))).size > 0, `Missing build asset: ${file}`);
}
const forbidden = /(?:^|\/)(?:\.env[^/]*|\.git|node_modules|api|docs|tools|tests)(?:\/|$)|\.(?:map|cpp|h|dart|pdf|docx|pem|key|p12|pfx)$/i;
async function inspect(dir, prefix = '') {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const relative = prefix + entry.name;
    assert.ok(!forbidden.test(relative), `Non-public artifact in deployment: ${relative}`);
    if (entry.isDirectory()) await inspect(path.join(dir, entry.name), relative + '/');
  }
}
await inspect(output);
const html = await readFile(path.join(output, 'index.html'), 'utf8');
assert.ok(!/<script(?![^>]*\bsrc=)[^>]*>\s*\S/i.test(html), 'No executable inline scripts');
const headers = Object.fromEntries(config.headers[0].headers.map(h => [h.key, h.value]));
assert.equal(headers['X-Content-Type-Options'], 'nosniff');
assert.ok(headers['Content-Security-Policy'].includes("frame-ancestors 'none'"));
assert.ok(!headers['Content-Security-Policy'].includes("'unsafe-eval'"));
console.log('Deployment verified: static app, local Wasm/CanvasKit, security headers, no source maps/secrets/server endpoints.');
