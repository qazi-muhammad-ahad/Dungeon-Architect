// Local release preview with the same security headers used on Vercel.
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const web = path.join(root, 'apps/flutter_ui/build/web');
const config = JSON.parse(await readFile(path.join(root, 'vercel.json'), 'utf8'));
const headers = Object.fromEntries(config.headers[0].headers.map(h => [h.key, h.value]));
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.css': 'text/css' };
const server = http.createServer(async (req, res) => {
  for (const [key, value] of Object.entries(headers)) res.setHeader(key, value);
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405, { Allow: 'GET, HEAD' }).end(); return; }
  try {
    let name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (name === '/') name = '/index.html';
    const file = path.resolve(web, '.' + name);
    if (!file.startsWith(web + path.sep) || !(await stat(file)).isFile()) { res.writeHead(404).end(); return; }
    res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
    const data = await readFile(file);
    res.writeHead(200).end(req.method === 'HEAD' ? undefined : data);
  } catch { res.writeHead(404).end(); }
});
server.listen(4173, '127.0.0.1', () => console.log('Release preview: http://127.0.0.1:4173'));
