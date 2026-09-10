// Launch hidden and capture diagnostics. Proxy failures are only a supplementary
// check; native APIs could bypass proxies, so also inspect process connections.
const {spawn, execFile} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const capture = process.argv.includes('--capture');
const benchmark = process.argv.includes('--benchmark');
const child = spawn('E:\\Godot_v4.7\\Godot_v4.7-stable_win64.exe',
  [...(capture || benchmark ? [] : ['--headless']), '--path', root, 'res://offline.tscn', '--',
    capture ? '--offline-capture' : benchmark ? '--offline-benchmark' : '--offline-test'],
  {cwd: root, windowsHide: true, env: {...process.env,
    HTTP_PROXY: 'http://127.0.0.1:9', HTTPS_PROXY: 'http://127.0.0.1:9',
    ALL_PROXY: 'http://127.0.0.1:9'}});
let output = '';
let connections = [];
let busy = false;
const monitor = setInterval(() => {
  if (busy) return;
  busy = true;
  execFile('powershell.exe', ['-NoProfile', '-Command',
    'Get-NetTCPConnection -OwningProcess ' + child.pid +
    ' -ErrorAction SilentlyContinue | Select-Object RemoteAddress,RemotePort,State | ConvertTo-Json -Compress'],
    {windowsHide: true}, (_, stdout) => {
      if (stdout.trim()) connections.push(stdout.trim());
      busy = false;
    });
}, 1500);
const timeout = setTimeout(() => { child.kill(); }, 600000);
child.stdout.on('data', b => {output += b; process.stdout.write(b);});
child.stderr.on('data', b => {output += b; process.stderr.write(b);});
child.on('error', e => {clearInterval(monitor);clearTimeout(timeout); throw e;});
child.on('exit', code => {
  clearInterval(monitor); clearTimeout(timeout);
  const success = code === 0 && output.includes(capture ? 'OFFLINE_CAPTURE 0' : benchmark ? 'OFFLINE_BENCHMARK PASS' : 'OFFLINE_ROUTE_TEST PASS');
  const result = {success, exit_code: code, invalid_proxy: true, sampled_tcp_connections: connections,
    physically_disconnected: false, output};
  fs.writeFileSync(path.join(__dirname, capture ? 'offline-capture-results.json' : benchmark ? 'offline-benchmark-results.json' : 'offline-results.json'),
    JSON.stringify(result, null, 2));
  process.exitCode = success && connections.length === 0 ? 0 : 1;
});
