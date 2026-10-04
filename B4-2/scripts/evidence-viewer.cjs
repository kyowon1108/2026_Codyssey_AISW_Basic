// Read-only localhost presentation of actual Docker evidence for screenshots.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const run = process.argv[2];
if (!/^\d{8}T\d{6}Z-\d+$/.test(run || '')) throw new Error('Expected run ID');
const base = path.join(root, 'docs/evidence', run);
const escape = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
function read(file) {
  try { return fs.readFileSync(path.join(base, file), 'utf8').replaceAll('\r', ''); }
  catch (error) { if (error.code === 'ENOENT') return '(not recorded yet)'; throw error; }
}
function block(file, text) {
  return `<section><h2>${escape(file)}</h2><pre>${escape(text ?? read(file))}</pre></section>`;
}
function tail(text, count) { return text.trimEnd().split('\n').slice(-count).join('\n'); }
function page(mode) {
  const titles = {environment: 'Docker environment and verification', oom: 'OOM / MEMORY_LIMIT comparison', cpu: 'CPU / CPU_MAX_OCCUPY comparison', deadlock: 'Deadlock / MULTI_THREAD_ENABLE comparison'};
  let content = '';
  if (mode === 'environment') {
    content = block('host-environment.txt') + block('environment.txt') + block('verification.txt');
  } else {
    for (const side of ['before', 'after']) {
      const name = `${mode}-${side}`;
      const config = read(`${name}/config.txt`).split('\n').filter(line => /^(MEMORY_LIMIT|CPU_MAX_OCCUPY|MULTI_THREAD_ENABLE)=/.test(line)).join('\n');
      const log = read(`${name}/application.log`);
      const selected = log.split('\n').filter(line => /Current Heap|Memory limit|Self-terminating|SELF-TERMINATED|Current Load|Threshold|WATCHDOG|LOCK ACQUIRED|Need resource|WAITING|All tasks completed/.test(line));
      const csv = read(`${name}/monitor.csv`).trimEnd().split('\n');
      const indices = [...new Set([0, 1, 2, 3, ...csv.map((_, i) => i).slice(-4)])];
      const samples = mode === 'deadlock' ? csv.slice(-6) : indices.filter(i => i < csv.length).map(i => csv[i]);
      content += `<article><h2 class="case">${name}</h2>`;
      content += block(`${name}/config.txt + result.txt`, config + '\n' + read(`${name}/result.txt`));
      const excerpt = mode === 'deadlock' && side === 'after'
        ? selected.filter(line => /All tasks completed/.test(line)).concat(selected.slice(-8))
        : selected.slice(-14);
      content += block(`${name}/application.log — matching raw lines`, excerpt.join('\n'));
      content += block(`${name}/monitor.csv — raw samples`, (mode === 'deadlock' ? csv[0] + '\n' : '') + samples.join('\n'));
      if (mode === 'deadlock') content += block(`${name}/process.txt — final ps / thread sample`, tail(read(`${name}/process.txt`), 22));
      if (mode === 'cpu') {
        const top = read(`${name}/top-threads.txt`);
        content += block(`${name}/top-threads.txt — final top -b -H -n 1 -p sample`, top.slice(top.lastIndexOf('top - ')));
      }
      content += '</article>';
    }
  }
  const note = mode === 'cpu' ? '<p class="note">Application Current Load and OS CPU measurements are different. This capture does not establish OS CPU saturation.</p>' : '';
  return `<!doctype html><meta charset="utf-8"><title>B4-2 ${titles[mode]}</title><style>
  *{box-sizing:border-box}body{margin:0;padding:28px;background:#f4f5f7;color:#18202b;font:14px system-ui}header{margin-bottom:18px}h1{margin:0 0 8px;font-size:25px}p{margin:5px 0}a{color:#22539b;margin-right:16px}main{display:grid;grid-template-columns:1fr 1fr;gap:18px}main.env{display:block}section{background:white;border:1px solid #cdd4dc;padding:12px;margin-bottom:12px;border-radius:5px}h2{font-size:12px;margin:0 0 9px;color:#3c5069;overflow-wrap:anywhere}h2.case{font-size:18px}pre{font:12px/1.5 ui-monospace,Menlo,monospace;margin:0;white-space:pre-wrap;overflow-wrap:anywhere}.note{background:#fff2c9;padding:12px}.env pre{font-size:14px}</style>
  <header><h1>${titles[mode]}</h1><p>Actual Docker output excerpts | run: ${run}</p><p>Source: B4-2/docs/evidence/${run}/ · CSV: UTC · application timestamps: KST</p><nav>${Object.keys(titles).map(key => `<a href="/?case=${key}">${key}</a>`).join('')}</nav>${note}</header><main class="${mode === 'environment' ? 'env' : ''}">${content}</main>`;
}
const server = http.createServer((request, response) => {
  const mode = new URL(request.url, 'http://localhost').searchParams.get('case') || 'environment';
  if (!['environment', 'oom', 'cpu', 'deadlock'].includes(mode)) { response.writeHead(404); response.end(); return; }
  response.writeHead(200, {'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store'});
  response.end(page(mode));
});
server.listen(0, '127.0.0.1', () => process.stdout.write(`http://127.0.0.1:${server.address().port}\n`));
